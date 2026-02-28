"""
shared.py – Shared utilities for the CAST and BugFinder agent pipelines.

Consolidates duplicated code from agent_cast.py, agent_bugfinder.py,
swebench_cast.py, swesmith_cast.py, and swesmith_bugfinder.py.

Contents
--------
- FileInput model (shared I/O schema)
- In-memory file store (_FILE_STORE) with accessor functions
- Generic LangChain tools: list_files, read_file
- Patch parsing helpers: extract_patch_files, extract_patch_hunks
- Python import analysis: python_imports, module_to_file
- Import-graph BFS: collect_neighbourhood
- SWE-smith repo cloning: clone_swesmith_repo
"""

from __future__ import annotations

import ast
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

from langchain.tools import tool
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# I/O models
# ---------------------------------------------------------------------------


class FileInput(BaseModel):
    """A single source file passed to an agent."""

    path: str = Field(description="Relative or absolute file path.")
    content: str = Field(description="Full source-code content of the file.")
    language: Optional[str] = Field(
        default=None,
        description="Programming language hint (auto-detected from extension when omitted).",
    )


# ---------------------------------------------------------------------------
# In-memory "file system" shared between tools
# ---------------------------------------------------------------------------

_FILE_STORE: Dict[str, str] = {}


def set_file_store(files: Dict[str, str]) -> None:
    """Replace the global file store with *files* (path → content)."""
    global _FILE_STORE
    _FILE_STORE = files


def get_file_store() -> Dict[str, str]:
    """Return the current file store dict (by reference)."""
    return _FILE_STORE


# ---------------------------------------------------------------------------
# Generic LangChain tools
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


# ---------------------------------------------------------------------------
# Patch parsing helpers
# ---------------------------------------------------------------------------


def extract_patch_files(patch: str) -> List[str]:
    """Return relative paths of files modified by a unified diff patch."""
    return re.findall(r"^--- a/(.+)$", patch, re.MULTILINE)


def extract_patch_hunks(patch: str) -> Dict[str, str]:
    """Return {file_path: unified diff text for that file}."""
    result: Dict[str, str] = {}
    current_file: Optional[str] = None
    current_lines: List[str] = []
    for line in patch.splitlines(keepends=True):
        m = re.match(r"^--- a/(.+)$", line)
        if m:
            if current_file:
                result[current_file] = "".join(current_lines)
            current_file = m.group(1)
            current_lines = [line]
        elif current_file:
            current_lines.append(line)
    if current_file:
        result[current_file] = "".join(current_lines)
    return result


# ---------------------------------------------------------------------------
# Python import analysis
# ---------------------------------------------------------------------------


def python_imports(path: Path) -> Set[str]:
    """Best-effort: return top-level module names referenced in a Python file."""
    try:
        source = path.read_text(encoding="utf-8", errors="replace")
        tree = ast.parse(source)
    except Exception:
        return set()
    names: Set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                names.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                names.add(node.module.split(".")[0])
    return names


def module_to_file(module: str, repo_root: Path) -> Optional[Path]:
    """Try to resolve a Python module name to a .py file inside *repo_root*."""
    parts = module.replace(".", "/")
    candidates = [
        repo_root / (parts + ".py"),
        repo_root / parts / "__init__.py",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


# ---------------------------------------------------------------------------
# Import-graph BFS neighbourhood expansion
# ---------------------------------------------------------------------------


def collect_neighbourhood(
    epicentre_files: List[Path],
    repo_root: Path,
    radius: int = 1,
    max_files: int = 30,
) -> List[Path]:
    """
    BFS expansion from *epicentre_files* through Python import edges.
    Returns at most *max_files* files (epicentre always included).
    """
    visited: Set[Path] = set(epicentre_files)
    frontier: Set[Path] = set(epicentre_files)

    for _ in range(radius):
        next_frontier: Set[Path] = set()
        for f in frontier:
            if not f.exists():
                continue
            for mod in python_imports(f):
                neighbour = module_to_file(mod, repo_root)
                if neighbour and neighbour not in visited:
                    visited.add(neighbour)
                    next_frontier.add(neighbour)
                    if len(visited) >= max_files:
                        break
            if len(visited) >= max_files:
                break
        frontier = next_frontier
        if not frontier:
            break

    return list(visited)[:max_files]


def collect_neighbourhood_extended(
    epicentre_files: List[Path],
    repo_root: Path,
    radius: int = 1,
    max_files: int = 10,
) -> List[Path]:
    """
    Like collect_neighbourhood but also includes sibling .py files in the same
    package directory (so the agent sees the full local context for single-file
    mutations).
    """
    visited: Set[Path] = set(epicentre_files)

    # Include siblings in the same directory (package context)
    for ep in epicentre_files:
        parent = ep.parent
        for sibling in parent.glob("*.py"):
            if sibling not in visited and len(visited) < max_files:
                visited.add(sibling)

    # Standard BFS expansion via imports
    frontier: Set[Path] = set(visited)
    for _ in range(radius):
        next_frontier: Set[Path] = set()
        for f in frontier:
            if not f.exists():
                continue
            for mod in python_imports(f):
                neighbour = module_to_file(mod, repo_root)
                if neighbour and neighbour not in visited:
                    visited.add(neighbour)
                    next_frontier.add(neighbour)
                    if len(visited) >= max_files:
                        break
            if len(visited) >= max_files:
                break
        frontier = next_frontier
        if not frontier:
            break

    return list(visited)[:max_files]


# ---------------------------------------------------------------------------
# SWE-smith repo cloning
# ---------------------------------------------------------------------------


def clone_swesmith_repo(repo_key: str) -> Path:
    """
    Clone a swesmith-registered repo (CWD-relative).
    Uses the swesmith mirror if available, falls back to GitHub.
    Returns the Path to the local clone.
    """
    from swesmith.profiles import registry

    rp = registry.get(repo_key)
    dir_path = rp.repo_name

    try:
        dir_path, cloned = rp.clone()
        print(f"  Cloned via mirror to: {dir_path}  (fresh={cloned})")
    except ValueError:
        if not os.path.exists(dir_path):
            print(f"  Mirror unavailable, cloning from GitHub...")
            subprocess.run(
                ["git", "clone",
                 f"https://github.com/{rp.owner}/{rp.repo}.git", dir_path],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                ["git", "checkout", "--detach", rp.commit],
                cwd=dir_path,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print(f"  Cloned from GitHub to: {dir_path}")
        else:
            print(f"  Using existing clone: {dir_path}")

    return Path(dir_path)
