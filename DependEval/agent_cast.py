"""
agent_cast.py – A generic, CAST-style ReAct dependency-analysis agent.

Design goals
------------
* **Input-format agnostic**: accepts any list of (path, content) pairs plus an
  optional natural-language query.  No coupling to the DependEval JSON schema.
* **CAST-inspired tooling**: tools mirror what CAST Imaging / CAST AIP do:
    - import / dependency extraction
    - directed dependency graph construction
    - call-chain tracing (BFS / DFS)
    - architectural-pattern detection (cycles, layers, entry-points)
* **Multi-agent plug-in interface**: the public `run_agent()` function accepts a
  `CodeAnalysisRequest` and returns a `CodeAnalysisResult` so it can be wired
  into a larger orchestrator with zero friction.

Usage (standalone experiment)
------------------------------
    from agent_cast import run_agent, CodeAnalysisRequest, FileInput

    req = CodeAnalysisRequest(
        files=[
            FileInput(path="utils.py",  content="..."),
            FileInput(path="main.py",   content="import utils\n..."),
        ],
        query="What are the dependency chains in this project?",
    )
    result = run_agent(req)
    print(result.dependency_graph)
    print(result.call_chains)
    print(result.summary)
"""

from __future__ import annotations

import json
import os
import re
from collections import deque
from typing import Any, Dict, List, Optional, Tuple

import networkx as nx
from langchain.tools import tool
from langchain_core.messages import HumanMessage, AIMessage
from langchain_anthropic import ChatAnthropic
from langchain.agents import create_agent
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Generic I/O models (no DependEval-specific fields)
# ---------------------------------------------------------------------------

class FileInput(BaseModel):
    """A single source file passed to the agent."""
    path: str = Field(description="Relative or absolute file path.")
    content: str = Field(description="Full source-code content of the file.")
    language: Optional[str] = Field(
        default=None,
        description="Programming language hint (python, java, javascript, …). "
                    "Auto-detected from extension when omitted.",
    )


class CodeAnalysisRequest(BaseModel):
    """Generic, format-agnostic input for the CAST analysis agent."""
    files: List[FileInput] = Field(
        description="One or more source files to analyse."
    )
    query: str = Field(
        default="Identify all dependency relationships and call chains between the provided files.",
        description="Natural-language task for the agent.",
    )
    max_graph_depth: int = Field(
        default=10,
        description="Maximum BFS depth when tracing call chains.",
    )


class CodeAnalysisResult(BaseModel):
    """Structured output returned by the agent – ready for a downstream orchestrator."""
    dependency_graph: Dict[str, List[str]] = Field(
        description="Adjacency list: {file -> [files it depends on]}."
    )
    call_chains: List[List[str]] = Field(
        description="All paths through the dependency graph (longest-path-first)."
    )
    entry_points: List[str] = Field(
        description="Files with no incoming dependencies (sources in the DAG)."
    )
    cycles: List[List[str]] = Field(
        description="Circular dependency groups detected."
    )
    summary: str = Field(
        description="Natural-language summary produced by the agent."
    )
    raw_agent_output: str = Field(
        description="Full agent trace / final answer for debugging."
    )


# ---------------------------------------------------------------------------
# In-memory "file system" shared between tools
# Populated once per run_agent() call via a closure.
# ---------------------------------------------------------------------------

_FILE_STORE: Dict[str, str] = {}   # path -> content
_GRAPH: nx.DiGraph = nx.DiGraph()


# ---------------------------------------------------------------------------
# Language-agnostic import extractor
# ---------------------------------------------------------------------------

# Patterns keyed by language (extension) – all yield (source_file, dep_hint)
_IMPORT_PATTERNS: Dict[str, List[re.Pattern]] = {
    "python":     [re.compile(r'^\s*(?:from\s+([\w./]+)\s+)?import\s+([\w./,\s]+)', re.MULTILINE)],
    "javascript": [re.compile(r'''(?:import|require)\s*\(?['"]([^'"]+)['"]\)?''')],
    "typescript": [re.compile(r'''(?:import|require)\s*\(?['"]([^'"]+)['"]\)?''')],
    "java":       [re.compile(r'^\s*import\s+([\w.]+);', re.MULTILINE)],
    "c":          [re.compile(r'#include\s*["<]([\w./]+)[">]')],
    "c++":        [re.compile(r'#include\s*["<]([\w./]+)[">]')],
    "c#":         [re.compile(r'^\s*using\s+([\w.]+);', re.MULTILINE)],
    "php":        [re.compile(r'''(?:require|include)(?:_once)?\s*\(?['"]([^'"]+)['"]\)?\s*;''')],
}


def _detect_language(path: str) -> str:
    ext = os.path.splitext(path)[-1].lower()
    return {
        ".py": "python", ".js": "javascript", ".ts": "typescript",
        ".java": "java", ".c": "c", ".cpp": "c++", ".cs": "c#", ".php": "php",
    }.get(ext, "python")


def _extract_raw_imports(path: str, content: str) -> List[str]:
    """Return raw import strings found in *content* for the file at *path*."""
    lang = _detect_language(path)
    patterns = _IMPORT_PATTERNS.get(lang, _IMPORT_PATTERNS["python"])
    hits: List[str] = []
    for pat in patterns:
        for m in pat.finditer(content):
            # capture first non-None group as the module reference
            ref = next((g for g in m.groups() if g), None)
            if ref:
                hits.append(ref.strip())
    return hits


def _resolve_import(raw: str, source_path: str, known_paths: List[str]) -> Optional[str]:
    """
    Try to match a raw import string to one of the known project files.
    Returns the matched path or None if it looks like an external package.
    """
    # Normalise: dots -> slashes for Python package paths
    normalised = raw.replace(".", "/")
    source_dir = os.path.dirname(source_path)

    candidates = [
        normalised,
        os.path.join(source_dir, normalised),
        raw,
        os.path.join(source_dir, raw),
    ]
    known_stems = {os.path.splitext(p)[0]: p for p in known_paths}
    known_base  = {os.path.basename(os.path.splitext(p)[0]): p for p in known_paths}

    for c in candidates:
        c_norm = os.path.normpath(c)
        if c_norm in known_stems:
            return known_stems[c_norm]
        base = os.path.basename(c_norm)
        if base in known_base:
            return known_base[base]
    return None


# ---------------------------------------------------------------------------
# LangChain tools
# ---------------------------------------------------------------------------

@tool
def list_files(_: str = "") -> str:
    """List all file paths currently loaded in the analysis context."""
    if not _FILE_STORE:
        return "No files loaded."
    return "\n".join(sorted(_FILE_STORE.keys()))


@tool
def read_file(path: str) -> str:
    """
    Read the content of a specific file from the analysis context.
    Input: file path (as returned by list_files).
    """
    content = _FILE_STORE.get(path)
    if content is None:
        # Try partial match
        for k, v in _FILE_STORE.items():
            if path in k or k.endswith(path):
                return v
        return f"File '{path}' not found. Available: {list(_FILE_STORE.keys())}"
    return content


@tool
def extract_imports(path: str) -> str:
    """
    Extract all import / dependency references from a single file.
    Returns a JSON list of raw import strings found in that file.
    Input: file path.
    """
    content = _FILE_STORE.get(path, "")
    if not content:
        return json.dumps([])
    raw = _extract_raw_imports(path, content)
    return json.dumps(raw)


@tool
def build_dependency_graph(_: str = "") -> str:
    """
    Analyse ALL loaded files, extract their imports, and resolve them to
    known project files.  Returns a JSON adjacency list
    {file: [files_it_depends_on]}.
    Also stores the graph internally for call-chain / cycle tools.
    """
    known = list(_FILE_STORE.keys())
    graph: Dict[str, List[str]] = {p: [] for p in known}

    _GRAPH.clear()
    _GRAPH.add_nodes_from(known)

    for src_path, content in _FILE_STORE.items():
        raw_imports = _extract_raw_imports(src_path, content)
        for raw in raw_imports:
            resolved = _resolve_import(raw, src_path, known)
            if resolved and resolved != src_path:
                graph[src_path].append(resolved)
                _GRAPH.add_edge(src_path, resolved)

    return json.dumps(graph, indent=2)


@tool
def trace_call_chains(max_depth: str = "10") -> str:
    """
    Enumerate all paths through the dependency graph (BFS from each entry-point).
    Returns a JSON list of paths [[file_a, file_b, file_c], ...].
    Optionally pass max_depth as a string integer.
    """
    if _GRAPH.number_of_nodes() == 0:
        return json.dumps([])

    depth = int(max_depth) if str(max_depth).isdigit() else 10

    # Entry points: nodes with no incoming edges
    entry_points = [n for n in _GRAPH.nodes() if _GRAPH.in_degree(n) == 0]
    if not entry_points:
        entry_points = list(_GRAPH.nodes())

    chains: List[List[str]] = []
    for start in entry_points:
        queue: deque[Tuple[List[str], int]] = deque()
        queue.append(([start], 0))
        while queue:
            path, d = queue.popleft()
            current = path[-1]
            successors = list(_GRAPH.successors(current))
            if not successors or d >= depth:
                if len(path) > 1:
                    chains.append(path)
            else:
                for nxt in successors:
                    if nxt not in path:          # avoid revisiting (simple path)
                        queue.append((path + [nxt], d + 1))

    # Deduplicate + sort by length desc
    seen = set()
    unique: List[List[str]] = []
    for c in sorted(chains, key=len, reverse=True):
        key = tuple(c)
        if key not in seen:
            seen.add(key)
            unique.append(c)

    return json.dumps(unique)


@tool
def detect_cycles(_: str = "") -> str:
    """
    Detect circular dependencies (strongly connected components with >1 node).
    Returns a JSON list of cycles [[file_a, file_b], ...].
    """
    if _GRAPH.number_of_nodes() == 0:
        return json.dumps([])
    sccs = [list(c) for c in nx.strongly_connected_components(_GRAPH) if len(c) > 1]
    return json.dumps(sccs)


@tool
def identify_entry_and_leaf_points(_: str = "") -> str:
    """
    Identify:
      - entry_points: files no other file imports (roots of the DAG).
      - leaf_points:  files that import nothing (leaves).
    Returns JSON {"entry_points": [...], "leaf_points": [...]}.
    """
    if _GRAPH.number_of_nodes() == 0:
        return json.dumps({"entry_points": [], "leaf_points": []})
    entries = [n for n in _GRAPH.nodes() if _GRAPH.in_degree(n) == 0]
    leaves  = [n for n in _GRAPH.nodes() if _GRAPH.out_degree(n) == 0]
    return json.dumps({"entry_points": entries, "leaf_points": leaves})


# ---------------------------------------------------------------------------
# System prompt & tool list
# ---------------------------------------------------------------------------

CAST_SYSTEM_PROMPT = (
    "You are a CAST-style software intelligence analyst. "
    "Your goal is to map the architecture of a software project by identifying "
    "file dependencies, call chains, circular dependencies, and architectural "
    "entry/exit points.\n\n"
    "Use the available tools to:\n"
    "  1. List all files in context.\n"
    "  2. Extract imports from each file.\n"
    "  3. Build the full dependency graph.\n"
    "  4. Trace call chains through the graph.\n"
    "  5. Detect any circular dependencies.\n"
    "  6. Identify entry and leaf points.\n\n"
    "When you have gathered all information, respond with a JSON object containing:\n"
    "  {\"dependency_graph\": {\"file\": [\"deps\"]}, "
    "\"call_chains\": [[\"...\"]],"
    "\"entry_points\": [\"...\"], "
    "\"cycles\": [[\"...\"]],"
    "\"summary\": \"natural-language explanation\"}"
)

_TOOLS = [
    list_files,
    read_file,
    extract_imports,
    build_dependency_graph,
    trace_call_chains,
    detect_cycles,
    identify_entry_and_leaf_points,
]


# ---------------------------------------------------------------------------
# Public multi-agent plug-in interface
# ---------------------------------------------------------------------------

# Type alias – the compiled LangGraph app returned by create_react_agent
CompiledAgent = Any


def build_agent(model_name: str = "claude-haiku-4-5", temperature: float = 0.0) -> CompiledAgent:
    """
    Build and return a LangGraph ReAct agent compiled graph.
    Can be called once and reused or wired into a larger orchestrator.
    """
    llm = ChatAnthropic(
        model=model_name,
        temperature=temperature,
        api_key=os.environ.get("ANTHROPIC_API_KEY", ""),
    )
    return create_agent(
        model=llm,
        tools=_TOOLS,
        system_prompt=CAST_SYSTEM_PROMPT,
    )


def run_agent(
    request: CodeAnalysisRequest,
    model_name: str = "claude-haiku-4-5",
    temperature: float = 0.0,
    agent_executor: Optional[CompiledAgent] = None,
) -> CodeAnalysisResult:
    """
    Run the CAST ReAct agent on a CodeAnalysisRequest.

    Parameters
    ----------
    request        : generic input (files + query) – no DependEval coupling.
    model_name     : Anthropic model identifier.
    temperature    : sampling temperature.
    agent_executor : optionally pass a pre-built compiled graph (multi-agent use).

    Returns
    -------
    CodeAnalysisResult – structured output ready for a downstream orchestrator.
    """
    # ---- Populate shared file store ----------------------------------------
    global _FILE_STORE, _GRAPH
    _FILE_STORE = {f.path: f.content for f in request.files}
    _GRAPH = nx.DiGraph()

    # ---- Build or reuse agent ----------------------------------------------
    if agent_executor is None:
        agent_executor = build_agent(model_name, temperature)

    # ---- Invoke ------------------------------------------------------------
    query = request.query
    raw_output = ""
    try:
        result = agent_executor.invoke(
            {"messages": [HumanMessage(content=query)]}
        )
        # LangGraph returns {"messages": [...]}; last AIMessage is the final answer
        messages = result.get("messages", [])
        for msg in reversed(messages):
            if isinstance(msg, AIMessage) and msg.content:
                raw_output = msg.content if isinstance(msg.content, str) else str(msg.content)
                break
        if not raw_output and messages:
            raw_output = str(messages[-1].content)
    except Exception as exc:
        raw_output = f"Agent error: {exc}"

    # ---- Parse structured JSON from the final answer -----------------------
    dependency_graph: Dict[str, List[str]] = {}
    call_chains: List[List[str]] = []
    entry_points: List[str] = []
    cycles: List[List[str]] = []
    summary = raw_output

    json_match = re.search(r'\{[\s\S]*\}', raw_output)
    if json_match:
        try:
            parsed = json.loads(json_match.group())
            dependency_graph = parsed.get("dependency_graph", {})
            call_chains      = parsed.get("call_chains", [])
            entry_points     = parsed.get("entry_points", [])
            cycles           = parsed.get("cycles", [])
            summary          = parsed.get("summary", raw_output)
        except json.JSONDecodeError:
            pass

    # Fallback: use the graph built by tools if the LLM output was not clean JSON
    if not dependency_graph and _GRAPH.number_of_nodes() > 0:
        dependency_graph = {n: list(_GRAPH.successors(n)) for n in _GRAPH.nodes()}
    if not entry_points and _GRAPH.number_of_nodes() > 0:
        entry_points = [n for n in _GRAPH.nodes() if _GRAPH.in_degree(n) == 0]
    if not cycles and _GRAPH.number_of_nodes() > 0:
        cycles = [list(c) for c in nx.strongly_connected_components(_GRAPH) if len(c) > 1]

    return CodeAnalysisResult(
        dependency_graph=dependency_graph,
        call_chains=call_chains,
        entry_points=entry_points,
        cycles=cycles,
        summary=summary,
        raw_agent_output=raw_output,
    )


# ---------------------------------------------------------------------------
# Convenience loader: build a CodeAnalysisRequest from arbitrary files on disk
# ---------------------------------------------------------------------------

def load_files_from_disk(
    paths: List[str],
    query: str = "Identify all dependency relationships and call chains.",
) -> CodeAnalysisRequest:
    """
    Helper to build a CodeAnalysisRequest from real files on disk.
    Completely independent of any DependEval JSON format.
    """
    files: List[FileInput] = []
    for p in paths:
        with open(p, "r", encoding="utf-8", errors="replace") as fh:
            files.append(FileInput(path=p, content=fh.read()))
    return CodeAnalysisRequest(files=files, query=query)


def load_files_from_dict(
    file_map: Dict[str, str],
    query: str = "Identify all dependency relationships and call chains.",
) -> CodeAnalysisRequest:
    """
    Helper to build a CodeAnalysisRequest from a plain {path: content} dict.
    Useful when content is already in memory (e.g. streamed from an IDE plugin
    or a larger multi-agent pipeline).
    """
    files = [FileInput(path=k, content=v) for k, v in file_map.items()]
    return CodeAnalysisRequest(files=files, query=query)


# ---------------------------------------------------------------------------
# CLI entry-point (quick experiment without touching run.py)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import glob

    parser = argparse.ArgumentParser(description="CAST-style dependency agent (experiment)")
    parser.add_argument("paths", nargs="+", help="Source files or glob patterns to analyse")
    parser.add_argument("--model",  default="claude-haiku-4-5")
    parser.add_argument("--query",  default="Identify all dependency relationships and call chains.")
    parser.add_argument("--out",    default=None, help="Optional JSON output file")
    args = parser.parse_args()

    # Expand globs
    resolved: List[str] = []
    for pattern in args.paths:
        expanded = glob.glob(pattern, recursive=True)
        resolved.extend(expanded if expanded else [pattern])

    print(f"Analysing {len(resolved)} file(s): {resolved}")

    req = load_files_from_disk(resolved, query=args.query)
    result = run_agent(req, model_name=args.model)

    out_data = result.model_dump()
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(out_data, fh, indent=2)
        print(f"Result saved to {args.out}")
    else:
        print(json.dumps(out_data, indent=2))
