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
import shlex
import subprocess
import textwrap
from pathlib import Path
from typing import Any, Dict, List, Optional

import anthropic
from langchain.agents import create_agent
from langchain.tools import tool
from langchain_anthropic import ChatAnthropic
from langchain_community.tools import ShellTool
from langchain_community.tools.file_management import ListDirectoryTool, ReadFileTool
from langchain_core.messages import AIMessage, HumanMessage
from pydantic import BaseModel, Field

from shared import (
    FileInput,
    list_files as shared_list_files,
    read_file as shared_read_file,
    get_file_store,
    set_file_store,
    get_repo_root,
    set_repo_root,
)

_COMMUNITY_TOOL_CACHE: Dict[str, Dict[str, Any]] = {}


def _get_community_tools() -> Optional[Dict[str, Any]]:
    """Return repo-scoped community tools, cached by absolute repo path."""
    repo_root = get_repo_root()
    if not repo_root:
        return None

    abs_root = str(Path(repo_root).resolve())
    cached = _COMMUNITY_TOOL_CACHE.get(abs_root)
    if cached:
        return cached

    tools = {
        "root": abs_root,
        "list": ListDirectoryTool(
            name="list_files",
            description="List files and directories relative to repository root.",
            root_dir=abs_root,
        ),
        "read": ReadFileTool(
            name="read_file",
            description="Read a file by path relative to repository root.",
            root_dir=abs_root,
        ),
        "shell": ShellTool(
            name="search_code",
            description="Search code with ripgrep over repository files.",
        ),
    }
    _COMMUNITY_TOOL_CACHE[abs_root] = tools
    return tools


@tool
def list_files(path: str = "") -> str:
    """List repository files and directories. Input optional subdirectory path."""
    community = _get_community_tools()
    if community:
        try:
            target = path.strip() or "."
            output = community["list"].run(target)
            return str(output) if output else "No files found."
        except Exception:
            pass
    return shared_list_files(path)


@tool
def read_file(path: str) -> str:
    """Read a file from repository context by relative path."""
    # Check in-memory file_store FIRST — patched (buggy) files live here.
    # The community "read" tool reads from disk, which has the clean/reverted
    # content after git apply --reverse, so it must only be used as a fallback.
    _file_store = get_file_store()
    if _file_store:
        # Exact match
        if path in _file_store:
            return _file_store[path]
        # Suffix/partial match (e.g. "flask/app.py" vs "src/flask/app.py")
        for k, v in _file_store.items():
            if k.endswith(path) or path.endswith(k):
                return v

    # Fall back to disk for non-patched context files
    community = _get_community_tools()
    if community:
        try:
            output = community["read"].run(path)
            return str(output)
        except Exception:
            pass
    return shared_read_file(path)

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
    community = _get_community_tools()
    if community:
        try:
            root = community["root"]
            rg_cmd = (
                f"cd {shlex.quote(root)} && "
                f"rg -n --no-heading --color never -m 30 -- {shlex.quote(pattern)} ."
            )
            output = str(community["shell"].run(rg_cmd)).strip()
            return output if output else "No matches found."
        except Exception:
            pass

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
# Tool: analyze_function – mutation-aware static analysis
# ---------------------------------------------------------------------------

def _op_symbol(node: ast.AST) -> str:
    """Return a human-readable symbol for an AST operator node."""
    _MAP = {
        ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.Div: "/",
        ast.FloorDiv: "//", ast.Mod: "%", ast.Pow: "**",
        ast.BitOr: "|", ast.BitAnd: "&", ast.BitXor: "^",
        ast.LShift: "<<", ast.RShift: ">>",
        ast.And: "and", ast.Or: "or", ast.Not: "not",
        ast.Eq: "==", ast.NotEq: "!=", ast.Lt: "<", ast.Gt: ">",
        ast.LtE: "<=", ast.GtE: ">=", ast.Is: "is", ast.IsNot: "is not",
        ast.In: "in", ast.NotIn: "not in",
    }
    return _MAP.get(type(node), type(node).__name__)


def _collect_operators(tree: ast.AST) -> List[Dict[str, Any]]:
    """Collect all operators used in expressions with context."""
    ops: List[Dict[str, Any]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.BinOp):
            ops.append({"line": node.lineno, "kind": "binary",
                        "op": _op_symbol(node.op),
                        "node": node})
        elif isinstance(node, ast.BoolOp):
            ops.append({"line": node.lineno, "kind": "boolean",
                        "op": _op_symbol(node.op),
                        "node": node})
        elif isinstance(node, ast.Compare):
            for i, cop in enumerate(node.ops):
                ops.append({"line": node.lineno, "kind": "compare",
                            "op": _op_symbol(cop),
                            "node": node})
        elif isinstance(node, ast.UnaryOp):
            ops.append({"line": node.lineno, "kind": "unary",
                        "op": _op_symbol(node.op),
                        "node": node})
    return ops


def _analyse_mutation_patterns(
    tree: ast.AST, func_src: str, func_name: str,
) -> List[str]:
    """Run all mutation-aware checks and return a list of findings."""
    issues: List[str] = []
    lines = func_src.strip().splitlines()

    # ---- bookkeeping sets ----
    assigned: set[str] = set()
    used: set[str] = set()
    params: set[str] = set()

    # Grab parameter names from the function def
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for a in node.args.args + node.args.posonlyargs + node.args.kwonlyargs:
                params.add(a.arg)
            if node.args.vararg:
                params.add(node.args.vararg.arg)
            if node.args.kwarg:
                params.add(node.args.kwarg.arg)
            break  # only the outermost function

    # ---- 1. Operator analysis (op_change / op_swap) ----
    all_ops = _collect_operators(tree)
    # Flag pairs of easily-confused operators
    _SWAP_PAIRS = {
        ("+", "-"), ("-", "+"), ("*", "/"), ("/", "*"),
        ("==", "!="), ("!=", "=="), ("<", ">"), (">", "<"),
        ("<=", ">="), (">=", "<="),
        ("and", "or"), ("or", "and"),
        ("|", "&"), ("&", "|"),
        ("is", "is not"), ("is not", "is"),
        ("in", "not in"), ("not in", "in"),
        ("//", "/"), ("/", "//"),
    }
    for op_info in all_ops:
        sym = op_info["op"]
        # Report all operators so the agent can reason about correctness
        issues.append(f"L{op_info['line']}: operator `{sym}` ({op_info['kind']})")

    # ---- 2. Assignment tracking (remove_assign) ----
    assign_lines: List[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assigned.add(target.id)
                    assign_lines.append((node.lineno, target.id))
        elif isinstance(node, ast.AugAssign):
            if isinstance(node.target, ast.Name):
                assigned.add(node.target.id)
                used.add(node.target.id)
                assign_lines.append((node.lineno, node.target.id))
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            used.add(node.id)

    # Variables used but never assigned (and not parameters/builtins/globals)
    _BUILTINS = {"True", "False", "None", "self", "cls", "super", "print",
                 "len", "range", "enumerate", "zip", "map", "filter", "str",
                 "int", "float", "bool", "list", "dict", "set", "tuple",
                 "type", "isinstance", "issubclass", "hasattr", "getattr",
                 "setattr", "callable", "iter", "next", "reversed", "sorted",
                 "min", "max", "sum", "abs", "round", "any", "all", "repr",
                 "id", "hash", "open", "ValueError", "TypeError", "KeyError",
                 "AttributeError", "RuntimeError", "Exception", "OSError",
                 "StopIteration", "NotImplementedError", "ImportError",
                 "IndexError", "FileNotFoundError", "IOError"}
    unassigned = used - assigned - params - _BUILTINS
    # Filter out module-level names (anything with a dot access is fine)
    if unassigned:
        issues.append(f"VARS_USED_NOT_ASSIGNED: {', '.join(sorted(unassigned)[:8])}")

    # Variables assigned but never used
    unused = assigned - used - {"_", "self", "cls"}
    if unused:
        issues.append(f"VARS_ASSIGNED_UNUSED: {', '.join(sorted(unused)[:8])}")

    # ---- 3. Control flow analysis (remove_cond / remove_loop) ----
    for node in ast.walk(tree):
        if isinstance(node, ast.If):
            body_len = len(node.body)
            else_len = len(node.orelse)
            if body_len == 1 and isinstance(node.body[0], ast.Pass):
                issues.append(f"L{node.lineno}: EMPTY_IF_BODY (pass only)")
            if node.orelse and else_len == 1 and isinstance(node.orelse[0], ast.Pass):
                issues.append(f"L{node.lineno}: EMPTY_ELSE_BODY (pass only)")
            if not node.orelse:
                issues.append(f"L{node.lineno}: IF_WITHOUT_ELSE")

        if isinstance(node, (ast.For, ast.While)):
            if len(node.body) == 1 and isinstance(node.body[0], ast.Pass):
                issues.append(f"L{node.lineno}: EMPTY_LOOP_BODY (pass only)")
            if len(node.body) == 0:
                issues.append(f"L{node.lineno}: EMPTY_LOOP_BODY (no statements)")

    # ---- 4. Return analysis ----
    returns = [n for n in ast.walk(tree) if isinstance(n, ast.Return)]
    if returns:
        with_value = [r for r in returns if r.value is not None]
        without_value = [r for r in returns if r.value is None]
        if with_value and without_value:
            issues.append("MIXED_RETURNS: some return a value, some don't")
        for r in returns:
            issues.append(f"L{r.lineno}: RETURN" +
                          (f" (with value)" if r.value else " (bare)"))

    # ---- 5. Method chain analysis (op_break_chains) ----
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute):
            # Check if an attribute is accessed but not called (broken chain)
            # This is hard to detect perfectly, but flag attribute accesses
            # that are standalone expressions (not part of a call)
            pass  # covered by the source-level check below

    # Source-level chain checks: look for lines with multiple dots that
    # seem incomplete (e.g., ending with a bare attribute, not a call)
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.count(".") >= 2 and not stripped.endswith(")") and \
           not stripped.endswith(":") and not stripped.startswith("#") and \
           not stripped.startswith("def ") and "import" not in stripped and \
           "=" not in stripped and stripped.endswith(","):
            issues.append(f"L{i}: POSSIBLE_BROKEN_CHAIN: {stripped[:80]}")

    # ---- 6. Constant / literal analysis (op_change_const) ----
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            if isinstance(node.value, bool):
                continue
            # Flag notable numeric constants
            v = node.value
            if v not in (0, 1, -1, 2, 0.0, 1.0, 100, 1000):
                issues.append(f"L{node.lineno}: CONSTANT: {v!r}")

    # ---- 7. Decorator / wrapper analysis (remove_wrapper) ----
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.decorator_list:
                for dec in node.decorator_list:
                    if isinstance(dec, ast.Name):
                        issues.append(f"L{dec.lineno}: DECORATOR: @{dec.id}")
                    elif isinstance(dec, ast.Attribute):
                        issues.append(f"L{dec.lineno}: DECORATOR: @...{dec.attr}")
                    elif isinstance(dec, ast.Call):
                        fn = dec.func
                        name = fn.id if isinstance(fn, ast.Name) else \
                               fn.attr if isinstance(fn, ast.Attribute) else "?"
                        issues.append(f"L{dec.lineno}: DECORATOR: @{name}(...)")

    # ---- 8. Statement order analysis (ctrl_shuffle) ----
    # Track first-use vs first-assign line for each variable
    first_assign: dict[str, int] = {}
    first_use: dict[str, int] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            name = node.id
            if isinstance(node.ctx, ast.Store):
                if name not in first_assign:
                    first_assign[name] = node.lineno
            elif isinstance(node.ctx, ast.Load):
                if name not in first_use:
                    first_use[name] = node.lineno
    for var in first_use:
        if var in first_assign and var not in params and var not in _BUILTINS:
            if first_use[var] < first_assign[var]:
                issues.append(f"L{first_use[var]}: USE_BEFORE_ASSIGN: `{var}` "
                              f"used at L{first_use[var]} but assigned at L{first_assign[var]}")

    # Enumerate ALL top-level statements inside the function so the agent can
    # reason about correct execution order (critical for ctrl_shuffle bugs)
    stmt_summary: List[str] = []
    func_node = None
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            func_node = node
            break
    if func_node:
        for stmt in func_node.body:
            lno = stmt.lineno
            if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant):
                stmt_summary.append(f"  L{lno}: [docstring/comment] {str(stmt.value.value)[:60]!r}")
            elif isinstance(stmt, ast.Assign):
                tgts = ", ".join(
                    t.id if isinstance(t, ast.Name) else ast.unparse(t)
                    for t in stmt.targets
                )
                stmt_summary.append(f"  L{lno}: [assign]  {tgts} = {ast.unparse(stmt.value)[:60]}")
            elif isinstance(stmt, ast.AugAssign):
                stmt_summary.append(f"  L{lno}: [augassign] {ast.unparse(stmt.target)} {ast.unparse(stmt)[:60]}")
            elif isinstance(stmt, ast.AnnAssign):
                stmt_summary.append(f"  L{lno}: [annassign] {ast.unparse(stmt.target)}")
            elif isinstance(stmt, ast.Return):
                val = ast.unparse(stmt.value) if stmt.value else "(nothing)"
                stmt_summary.append(f"  L{lno}: [return]   {val[:60]}")
            elif isinstance(stmt, ast.If):
                stmt_summary.append(f"  L{lno}: [if]       {ast.unparse(stmt.test)[:60]}")
            elif isinstance(stmt, (ast.For, ast.While)):
                kind = "for" if isinstance(stmt, ast.For) else "while"
                test = ast.unparse(stmt.target if isinstance(stmt, ast.For) else stmt.test)
                stmt_summary.append(f"  L{lno}: [{kind}]     {test[:60]}")
            elif isinstance(stmt, ast.Try):
                stmt_summary.append(f"  L{lno}: [try]")
            elif isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
                stmt_summary.append(f"  L{lno}: [def]      {stmt.name}")
            elif isinstance(stmt, ast.ClassDef):
                stmt_summary.append(f"  L{lno}: [class]    {stmt.name}")
            elif isinstance(stmt, ast.Raise):
                stmt_summary.append(f"  L{lno}: [raise]    {ast.unparse(stmt.exc) if stmt.exc else ''}[:60]")
            else:
                stmt_summary.append(f"  L{lno}: [stmt]     {ast.unparse(stmt)[:60]}")
        if stmt_summary:
            issues.insert(0, "STATEMENT_ORDER (top-level body, in current order):\n" + "\n".join(stmt_summary))

    # ---- 9. Short body / structural anomalies ----
    if len(lines) <= 2:
        issues.append("VERY_SHORT_BODY: <=2 lines – possibly missing logic")

    # ---- Summary header ----
    n_ops = len(all_ops)
    n_assigns = len(assign_lines)
    n_ifs = sum(1 for n in ast.walk(tree) if isinstance(n, ast.If))
    n_loops = sum(1 for n in ast.walk(tree) if isinstance(n, (ast.For, ast.While)))
    header = (f"Analysis of `{func_name}` ({len(lines)} lines, "
              f"{n_ops} operators, {n_assigns} assignments, "
              f"{n_ifs} if-blocks, {n_loops} loops):")

    if not issues:
        return header + "\n  No anomalies detected."
    return header + "\n" + "\n".join(f"  - {i}" for i in issues)


@tool
def analyze_function(input_str: str) -> str:
    """
    Mutation-aware static analysis of a Python function.
    Checks for ALL common synthetic mutation patterns:
    - Operator anomalies (wrong/swapped operators, comparisons)
    - Missing assignments (variables used but never assigned)
    - Unused assignments (assigned but never read)
    - Missing conditionals (if without else, empty branches)
    - Empty loop bodies
    - Use-before-assignment (shuffled statements)
    - Suspicious constants/literals
    - Missing decorators/wrappers
    - Broken method chains
    - Mixed return patterns

    Reports ALL operators, assignments, and control flow so you can
    reason about which element is incorrect.

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

    try:
        tree = ast.parse(textwrap.dedent(func_src))
    except SyntaxError:
        return f"Could not parse function '{func_name}' (syntax error)."

    return _analyse_mutation_patterns(tree, func_src, func_name)


# ---------------------------------------------------------------------------
# Tool: run_python – execute Python code in the repo
# ---------------------------------------------------------------------------

@tool
def run_python(code: str) -> str:
    """
    Execute a Python code snippet inside the repository directory.
    The repo's source tree is on sys.path so you can import project modules.
    Useful for:
    - Importing a function and calling it to see runtime errors
    - Writing a small test to verify expected vs actual behaviour
    - Checking types, return values, or side-effects

    Returns stdout + stderr (truncated to 3000 chars). Timeout: 30s.
    Input: Python source code as a string.
    """
    repo_root = get_repo_root()
    if not repo_root:
        return "Error: no repo root configured — cannot execute code."

    try:
        result = subprocess.run(
            ["python", "-c", code],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=repo_root,
            env={**os.environ, "PYTHONPATH": f"{repo_root}/src:{repo_root}:{os.environ.get('PYTHONPATH', '')}"},
        )
        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            output += "\n--- STDERR ---\n" + result.stderr
        if result.returncode != 0:
            output += f"\n[exit code: {result.returncode}]"
        if not output.strip():
            output = "(no output)"
        return output[:3000]
    except subprocess.TimeoutExpired:
        return "Error: execution timed out (30s limit)."
    except Exception as e:
        return f"Error running code: {e}"


@tool
def run_tests(test_path: str = "") -> str:
    """
    Run the project's test suite (or a specific test file/directory) using pytest.
    Returns the test output (truncated to 4000 chars). Timeout: 60s.

    Input: optional path to a specific test file or directory.
           Leave empty to run the full test suite (may be slow).
    Examples:
      "tests/test_helpers.py"
      "tests/test_helpers.py::test_stream"
      ""  (runs all tests)
    """
    repo_root = get_repo_root()
    if not repo_root:
        return "Error: no repo root configured — cannot run tests."

    cmd = ["python", "-m", "pytest", "-x", "-q", "--tb=short", "--no-header"]
    if test_path.strip():
        cmd.append(test_path.strip())

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60,
            cwd=repo_root,
            env={**os.environ, "PYTHONPATH": f"{repo_root}/src:{repo_root}:{os.environ.get('PYTHONPATH', '')}"},
        )
        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            # Filter out common pytest warnings noise
            stderr_lines = [l for l in result.stderr.splitlines()
                          if not l.strip().startswith(("Warning", "DeprecationWarning", "PytestUnraisableExceptionWarning"))]
            if stderr_lines:
                output += "\n--- STDERR ---\n" + "\n".join(stderr_lines)
        if not output.strip():
            output = "(no output)"
        return output[:4000]
    except subprocess.TimeoutExpired:
        return "Error: test execution timed out (60s limit). Try a specific test file instead."
    except Exception as e:
        return f"Error running tests: {e}"


# ---------------------------------------------------------------------------
# System prompt
# ---------------------------------------------------------------------------

BUGFINDER_SYSTEM_PROMPT = """\
You are a bug-finding agent. A synthetic bug was injected into ONE Python function.

STEP 1 – READ the target function: read_function("file_path::function_name")
STEP 2 – ANALYSE: analyze_function("file_path::function_name")
         Pay close attention to the STATEMENT_ORDER section — it lists every
         top-level statement with its line number in current (possibly wrong) order.
         For shuffled-statement bugs the fix is to reorder those statements.
STEP 3 – OUTPUT your JSON. The JSON must have exactly these keys:

  buggy_file           – file path
  buggy_function       – function name
  root_cause_analysis  – 1-2 sentences: what is wrong and why it breaks behaviour
  fix_suggestion       – the COMPLETE corrected function body as a Python code block.
                         Do NOT write "move line X" — write the actual fixed code.
                         Example style:
                           ```python
                           def my_func(x):
                               correct_line_1
                               correct_line_2
                               return result
                           ```
  confidence           – low / medium / high
  summary              – one sentence headline

RULES:
- The bug EXISTS. Never say "no bug found".
- fix_suggestion MUST contain corrected code. Generic descriptions score zero.
- Your FINAL message must contain ONLY the JSON object (no extra text).
"""

_TOOLS = [
    list_files,
    read_file,
    get_file_outline,
    read_function,
    search_code,
    analyze_function,
    run_python,
    run_tests,
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
        max_tokens=2048,
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
    hint_file: str = "",
    hint_function: str = "",
) -> BugAnalysisResult:
    """
    Run the BugFinder ReAct agent on a BugAnalysisRequest.

    Returns
    -------
    BugAnalysisResult - structured output ready for an LLM judge.
    """
    set_file_store({f.path: f.content for f in request.files})

    if agent_executor is None:
        agent_executor = build_agent(model_name, temperature)

    raw_output = ""
    try:
        result = agent_executor.invoke(
            {"messages": [HumanMessage(content=request.query)]},
            {"recursion_limit": 80},
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

    # Fallback: if no JSON was extracted, ask an LLM to pull structure from prose
    if not buggy_file and not buggy_function and len(raw_output) > 50:
        try:
            client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))
            resp = client.messages.create(
                model=model_name,
                max_tokens=512,
                system="Extract the bug analysis from the text below into a JSON object with keys: buggy_file, buggy_function, root_cause_analysis, fix_suggestion, confidence, summary. Respond with ONLY the JSON.",
                messages=[{"role": "user", "content": raw_output[-3000:]}],
            )
            fallback_text = resp.content[0].text.strip()
            fb_match = re.search(r'\{[\s\S]*\}', fallback_text)
            if fb_match:
                parsed = json.loads(fb_match.group())
                buggy_file     = parsed.get("buggy_file", "")
                buggy_function = parsed.get("buggy_function", "")
                root_cause     = parsed.get("root_cause_analysis", "")
                fix_suggestion = parsed.get("fix_suggestion", "")
                confidence     = parsed.get("confidence", "medium")
                summary        = parsed.get("summary", raw_output[:200])
        except Exception:
            pass  # fallback failed, proceed with empty fields

    # Apply hints only for fields the agent left completely blank
    if not buggy_file and hint_file:
        buggy_file = hint_file
    if not buggy_function and hint_function:
        buggy_function = hint_function

    return BugAnalysisResult(
        buggy_file=buggy_file,
        buggy_function=buggy_function,
        root_cause_analysis=root_cause,
        fix_suggestion=fix_suggestion,
        confidence=str(confidence),
        summary=str(summary) if summary else "",
        raw_agent_output=raw_output,
    )
