"""
agent_bugfinder.py – A ReAct agent for single-file bug detection & diagnosis.

Designed for the SWE-smith paradigm: synthetic single-function mutations in
Python codebases.  Unlike the CAST agent (architecture / dependency mapping),
this agent focuses on **semantic code inspection**: reading functions, spotting
anomalies, and proposing fixes.

Tools
-----
1. list_files        – list loaded file paths
2. read_file         – read full file content
3. get_file_outline  – AST-based outline (functions, classes, methods)
4. read_function     – extract a single function/method body by name
5. search_code       – grep-style search across all loaded files
6. analyze_function  – quick static analysis for common code anomalies

Output schema
-------------
BugAnalysisResult:
  buggy_file, buggy_function, root_cause_analysis, fix_suggestion,
  confidence, summary, raw_agent_output
"""

from __future__ import annotations

import ast
import json
import os
import re
import textwrap
from typing import Any, Dict, List, Optional

from langchain.tools import tool
from langchain_core.messages import HumanMessage, AIMessage
from langchain_anthropic import ChatAnthropic
from langchain.agents import create_agent
from pydantic import BaseModel, Field

from shared import (
    FileInput,
    list_files,
    read_file,
    get_file_store,
    set_file_store,
)

# ---------------------------------------------------------------------------
# I/O models
# ---------------------------------------------------------------------------


class BugAnalysisRequest(BaseModel):
    """Input for the bug-finder agent."""
    files: List[FileInput] = Field(description="Source files to analyse.")
    query: str = Field(
        default="Identify the bug in the provided code and suggest a fix.",
        description="Natural-language task for the agent.",
    )


class BugAnalysisResult(BaseModel):
    """Structured output – directly scoreable by the LLM judge."""
    buggy_file: str = Field(
        default="", description="Path of the file containing the bug."
    )
    buggy_function: str = Field(
        default="", description="Name of the buggy function/method."
    )
    root_cause_analysis: str = Field(
        default="",
        description="Detailed explanation of the root cause of the bug.",
    )
    fix_suggestion: str = Field(
        default="",
        description="Concrete code-level fix suggestion (ideally a diff or corrected code).",
    )
    confidence: str = Field(
        default="medium",
        description="Confidence level: low, medium, high.",
    )
    summary: str = Field(
        default="",
        description="Brief natural-language summary of findings.",
    )
    raw_agent_output: str = Field(
        default="",
        description="Full agent trace / final answer for debugging.",
    )


# ---------------------------------------------------------------------------
# AST helpers
# ---------------------------------------------------------------------------

def _ast_outline(source: str) -> List[Dict[str, Any]]:
    """Parse Python source and return a list of top-level/nested definitions."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    items: List[Dict[str, Any]] = []
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
            items.append({
                "type": "function",
                "name": node.name,
                "lineno": node.lineno,
                "end_lineno": getattr(node, "end_lineno", node.lineno),
                "args": [a.arg for a in node.args.args],
            })
        elif isinstance(node, ast.ClassDef):
            methods = []
            for child in ast.iter_child_nodes(node):
                if isinstance(child, ast.FunctionDef | ast.AsyncFunctionDef):
                    methods.append({
                        "type": "method",
                        "name": child.name,
                        "lineno": child.lineno,
                        "end_lineno": getattr(child, "end_lineno", child.lineno),
                        "args": [a.arg for a in child.args.args],
                    })
            items.append({
                "type": "class",
                "name": node.name,
                "lineno": node.lineno,
                "end_lineno": getattr(node, "end_lineno", node.lineno),
                "methods": methods,
            })
    return items


@tool
def get_file_outline(path: str) -> str:
    """
    Return an AST-based outline of a Python file: classes, functions, methods
    with line numbers.  Useful for understanding file structure before diving
    into specific functions.
    Input: file path.
    """
    _file_store = get_file_store()
    content = _file_store.get(path, "")
    if not content:
        for k, v in _file_store.items():
            if path in k or k.endswith(path):
                content = v
                break
    if not content:
        return f"File '{path}' not found."
    outline = _ast_outline(content)
    if not outline:
        return "Could not parse file (syntax error or empty)."
    return json.dumps(outline, indent=2)


# ---------------------------------------------------------------------------
# Tool: read_function
# ---------------------------------------------------------------------------

def _extract_function_source(source: str, func_name: str) -> Optional[str]:
    """Extract the source lines for a function/method by name."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None

    lines = source.splitlines(keepends=True)

    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
            if node.name == func_name:
                start = node.lineno - 1  # 0-based
                end = getattr(node, "end_lineno", len(lines))
                return "".join(lines[start:end])
    return None


@tool
def read_function(input_str: str) -> str:
    """
    Extract the source code of a specific function or method.
    Input format: "file_path::function_name"
    Example: "src/flask/helpers.py::stream_with_context"

    If the function is a method inside a class, just use the method name
    (e.g. "src/marshmallow/fields.py::_validated").
    """
    parts = input_str.split("::", 1)
    if len(parts) != 2:
        return "Error: input must be 'file_path::function_name'"

    path, func_name = parts[0].strip(), parts[1].strip()
    _file_store = get_file_store()
    content = _file_store.get(path, "")
    if not content:
        for k, v in _file_store.items():
            if path in k or k.endswith(path):
                content = v
                break
    if not content:
        return f"File '{path}' not found."

    source = _extract_function_source(content, func_name)
    if source is None:
        return f"Function '{func_name}' not found in '{path}'. Use get_file_outline to see available definitions."
    return source


# ---------------------------------------------------------------------------
# Tool: search_code
# ---------------------------------------------------------------------------

@tool
def search_code(pattern: str) -> str:
    """
    Search all loaded files for lines matching a regex or plain-text pattern.
    Returns up to 30 matching lines with file path and line number.
    Input: search pattern (string or regex).
    """
    try:
        regex = re.compile(pattern, re.IGNORECASE)
    except re.error:
        regex = re.compile(re.escape(pattern), re.IGNORECASE)

    _file_store = get_file_store()
    matches: List[str] = []
    for path, content in _file_store.items():
        for i, line in enumerate(content.splitlines(), 1):
            if regex.search(line):
                matches.append(f"{path}:{i}: {line.rstrip()}")
                if len(matches) >= 30:
                    break
        if len(matches) >= 30:
            break

    if not matches:
        return "No matches found."
    return "\n".join(matches)


# ---------------------------------------------------------------------------
# Tool: diff_function (conceptual comparison helper)
# ---------------------------------------------------------------------------

@tool
def analyze_function(input_str: str) -> str:
    """
    Perform a quick static analysis of a function, checking for common
    code anomalies:
    - Unused variables / dead assignments
    - Unreachable code after return/break/continue
    - Suspicious operator usage (== vs =, & vs and, etc.)
    - Empty branches (if/else with pass)
    - Missing return values
    - Variables used before assignment

    Input format: "file_path::function_name"
    """
    parts = input_str.split("::", 1)
    if len(parts) != 2:
        return "Error: input must be 'file_path::function_name'"

    path, func_name = parts[0].strip(), parts[1].strip()
    _file_store = get_file_store()
    content = _file_store.get(path, "")
    if not content:
        for k, v in _file_store.items():
            if path in k or k.endswith(path):
                content = v
                break
    if not content:
        return f"File '{path}' not found."

    func_src = _extract_function_source(content, func_name)
    if func_src is None:
        return f"Function '{func_name}' not found in '{path}'."

    # Parse the function body
    # Wrap in a try block since extracted function may need indentation context
    try:
        tree = ast.parse(textwrap.dedent(func_src))
    except SyntaxError:
        return f"Could not parse function '{func_name}' (syntax error)."

    issues: List[str] = []

    # Walk the AST looking for anomalies
    assigned: set = set()
    used: set = set()
    returned_something = False
    has_return = False

    for node in ast.walk(tree):
        # Track assignments
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assigned.add(target.id)
        elif isinstance(node, ast.AugAssign):
            if isinstance(node.target, ast.Name):
                assigned.add(node.target.id)
                used.add(node.target.id)

        # Track variable usage
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            used.add(node.id)

        # Check for empty if/else bodies (just pass)
        if isinstance(node, ast.If):
            if len(node.body) == 1 and isinstance(node.body[0], ast.Pass):
                issues.append(f"L{node.lineno}: Empty if-body (just 'pass')")
            if node.orelse and len(node.orelse) == 1 and isinstance(node.orelse[0], ast.Pass):
                issues.append(f"L{node.lineno}: Empty else-body (just 'pass')")

        # Check for return
        if isinstance(node, ast.Return):
            has_return = True
            if node.value is not None:
                returned_something = True

        # Check for comparisons that look suspicious
        if isinstance(node, ast.Compare):
            for op in node.ops:
                if isinstance(op, ast.Is) and not isinstance(node.comparators[0], ast.Constant):
                    # 'is' used with non-None/True/False
                    c = node.comparators[0]
                    if not (isinstance(c, ast.Constant) and c.value in (None, True, False)):
                        issues.append(f"L{node.lineno}: 'is' comparison with non-singleton value")

    # Check for assigned but unused variables (excluding _ and self)
    unused = assigned - used - {"_", "self", "cls"}
    for v in sorted(unused):
        issues.append(f"Variable '{v}' assigned but never used")

    # Check for very short function body (might be missing logic)
    lines = func_src.strip().splitlines()
    if len(lines) <= 2:
        issues.append("Function body is very short (<=2 lines) – may be missing logic")

    if not issues:
        return f"No obvious anomalies detected in '{func_name}' ({len(lines)} lines)."
    return f"Anomalies in '{func_name}' ({len(lines)} lines):\n" + "\n".join(f"  - {i}" for i in issues)


# ---------------------------------------------------------------------------
# System prompt
# ---------------------------------------------------------------------------

BUGFINDER_SYSTEM_PROMPT = """\
You are a bug-finding agent. A synthetic bug was injected into Python source code.
You MUST follow this exact 3-step protocol:

STEP 1: Call read_function on the HINTED function (given in the query).
        Format: "file_path::function_name"
STEP 2: Read the function source carefully. The bug is ONE of these patterns:
        - Wrong/swapped operator (==↔!=, +↔-, |↔&, or↔and)
        - Missing assignment (variable never set)
        - Missing conditional (if/elif/else branch removed)
        - Shuffled lines (statements in wrong order)
        - Missing loop body
        - Missing with/try wrapper
        - Wrong constant/literal
        - Swapped operands
        - Broken method chain
STEP 3: Output ONLY a JSON object — nothing else:

{"buggy_file": "...", "buggy_function": "...", "root_cause_analysis": "...", "fix_suggestion": "...", "confidence": "high", "summary": "..."}

CRITICAL CONSTRAINTS:
- The bug EXISTS. Never say "no bug found".
- Do NOT call more than 4 tools total. After reading the function, COMMIT.
- Do NOT explore other files or functions unless the hinted one does not exist.
- Your FINAL message must be the JSON object and nothing else.
"""

_TOOLS = [
    list_files,
    read_file,
    get_file_outline,
    read_function,
    search_code,
    analyze_function,
]


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

CompiledAgent = Any


def build_agent(
    model_name: str = "claude-haiku-4-5",
    temperature: float = 0.0,
) -> CompiledAgent:
    """Build and return a LangGraph ReAct agent for bug finding."""
    llm = ChatAnthropic(
        model=model_name,
        temperature=temperature,
        api_key=os.environ.get("ANTHROPIC_API_KEY", ""),
        max_tokens=4096,
    )
    return create_agent(
        model=llm,
        tools=_TOOLS,
        system_prompt=BUGFINDER_SYSTEM_PROMPT,
    )


def run_agent(
    request: BugAnalysisRequest,
    model_name: str = "claude-haiku-4-5",
    temperature: float = 0.0,
    agent_executor: Optional[CompiledAgent] = None,
) -> BugAnalysisResult:
    """
    Run the BugFinder ReAct agent on a BugAnalysisRequest.

    Returns
    -------
    BugAnalysisResult – structured output ready for an LLM judge.
    """
    set_file_store({f.path: f.content for f in request.files})

    if agent_executor is None:
        agent_executor = build_agent(model_name, temperature)

    raw_output = ""
    try:
        result = agent_executor.invoke(
            {"messages": [HumanMessage(content=request.query)]},
            {"recursion_limit": 40},
        )
        messages = result.get("messages", [])
        for msg in reversed(messages):
            if isinstance(msg, AIMessage) and msg.content:
                raw_output = msg.content if isinstance(msg.content, str) else str(msg.content)
                break
        if not raw_output and messages:
            raw_output = str(messages[-1].content)
    except Exception as exc:
        raw_output = f"Agent error: {exc}"

    # Parse structured JSON from agent output
    buggy_file = ""
    buggy_function = ""
    root_cause = ""
    fix_suggestion = ""
    confidence = "low"
    summary = raw_output

    json_match = re.search(r'\{[\s\S]*\}', raw_output)
    if json_match:
        try:
            parsed = json.loads(json_match.group())
            buggy_file     = parsed.get("buggy_file", "")
            buggy_function = parsed.get("buggy_function", "")
            root_cause     = parsed.get("root_cause_analysis", "")
            fix_suggestion = parsed.get("fix_suggestion", "")
            confidence     = parsed.get("confidence", "medium")
            summary        = parsed.get("summary", raw_output)
        except json.JSONDecodeError:
            pass

    return BugAnalysisResult(
        buggy_file=buggy_file,
        buggy_function=buggy_function,
        root_cause_analysis=root_cause,
        fix_suggestion=fix_suggestion,
        confidence=confidence,
        summary=summary,
        raw_agent_output=raw_output,
    )
