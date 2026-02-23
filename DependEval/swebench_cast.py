"""
swebench_cast.py – Run the CAST ReAct dependency agent on real SWE-bench repos.

For each selected SWE-bench instance the script:
  1. Loads instance metadata (problem statement, patch, base commit) from HF.
  2. Shallow-clones the repo at the base commit into a local cache.
  3. Extracts the files touched by the patch (the "epicentre").
  4. Collects their immediate neighbours (files that import them or are
     imported by them) up to a configurable radius.
  5. Feeds all collected files + the problem statement into agent_cast.run_agent().
  6. Saves a rich JSON result per instance.

Usage
-----
    # Quickstart – runs the default 5 instances with Haiku
    uv run python swebench_cast.py

    # Custom run
    uv run python swebench_cast.py \\
        --instances astropy__astropy-12907 psf__requests-2317 pytest-dev__pytest-5809 \\
        --model claude-haiku-4-5 \\
        --radius 1 \\
        --out_dir results/swebench_cast
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import anthropic

from datasets import load_dataset

from agent_cast import (
    CodeAnalysisRequest,
    CodeAnalysisResult,
    FileInput,
    build_agent,
    run_agent,
)

# ---------------------------------------------------------------------------
# Default instances – one per repo family, chosen for small patch surface
# ---------------------------------------------------------------------------

DEFAULT_INSTANCES = [
    # ── astropy (3) ────────────────────────────────────────────────────────
    "astropy__astropy-12907",    # separability_matrix nested CompoundModels
    "astropy__astropy-14365",    # QDP case-sensitivity (io/ascii)
    "astropy__astropy-14182",    # RST header rows (io/ascii)
    # ── psf/requests (4) ───────────────────────────────────────────────────
    "psf__requests-2317",        # binary-string HTTP method bug
    "psf__requests-1963",        # session adapter URL hook
    "psf__requests-2148",        # model encoding bug
    "psf__requests-2674",        # adapter max-retry arg
    # ── pytest-dev/pytest (3) ──────────────────────────────────────────────
    "pytest-dev__pytest-5103",   # assertion rewrite edge-case
    "pytest-dev__pytest-5221",   # python plugin parametrize
    "pytest-dev__pytest-5227",   # logging plugin
    # ── sympy (3) ──────────────────────────────────────────────────────────
    "sympy__sympy-13031",        # hstack/vstack zero-row matrix
    "sympy__sympy-11400",        # C code printer
    "sympy__sympy-11870",        # trig simplification
    # ── matplotlib (2) ─────────────────────────────────────────────────────
    "matplotlib__matplotlib-22711",  # widget interaction
    "matplotlib__matplotlib-22835",  # artist.set() kwarg
    # ── scikit-learn (2) ───────────────────────────────────────────────────
    "scikit-learn__scikit-learn-10297",  # ridge regression alpha
    "scikit-learn__scikit-learn-10508",  # LabelEncoder unique dtype
    # ── sphinx-doc (1) ─────────────────────────────────────────────────────
    "sphinx-doc__sphinx-10451",  # autodoc typehints
    # ── pylint-dev (1) ─────────────────────────────────────────────────────
    "pylint-dev__pylint-5859",   # fixme checker
    # ── pydata/xarray (1) ──────────────────────────────────────────────────
    "pydata__xarray-3364",       # concat axis bug
]

REPO_CACHE_DIR = Path(".swebench_repos")   # shallow clones cached here
RESULTS_DIR    = Path("results/swebench_cast")

# ---------------------------------------------------------------------------
# LLM-as-judge evaluation
# ---------------------------------------------------------------------------

_JUDGE_SYSTEM = """\
You are an expert software-engineering judge. Your task is to evaluate how well
a static-analysis agent identified and explained a bug, given the actual ground-truth patch.

Respond ONLY with a valid JSON object – no markdown fences, no extra text.
"""

_JUDGE_USER = """\
## Problem statement (what the user reported)
{problem}

## Ground-truth patch (the actual fix committed)
```diff
{patch}
```

## Agent analysis (what the CAST agent produced)
### Dependency graph
{dep_graph}

### Call chains
{call_chains}

### Agent summary
{summary}

---
Score the agent analysis on the following criteria and return a JSON object with
exactly these keys:

- "file_correct"        (bool)   – did the agent identify the correct file(s) being patched?
- "function_correct"   (bool)   – did the agent name at least one of the functions actually changed in the patch?
- "root_cause_score"   (int 0-5) – how accurately does the agent describe the root cause?
  0=completely wrong, 3=partially correct, 5=exact match
- "fix_suggestion_score" (int 0-5) – how close is the agent's suggested fix to the actual patch?
  0=no fix suggested or wrong direction, 3=correct approach but incomplete, 5=exactly the patch applied
- "overall"            (int 0-5) – holistic quality of the architectural analysis
- "rationale"          (string)  – 2-3 sentences justifying your scores, noting what was correct/missing
"""


def judge_result(
    record: Dict[str, Any],
    patch_diff: str,
    model_name: str = "claude-haiku-4-5",
) -> Dict[str, Any]:
    """Call an LLM judge to score the CAST agent's analysis against the ground-truth patch."""
    cr = record.get("cast_result", {})
    dep_graph_str = json.dumps(cr.get("dependency_graph", {}), indent=2)
    call_chains_str = json.dumps(cr.get("call_chains", []), indent=2)
    summary_str = cr.get("summary", "(no summary)")
    problem_str = record.get("problem_statement", "")

    user_msg = _JUDGE_USER.format(
        problem=problem_str[:800],
        patch=patch_diff[:2000],
        dep_graph=dep_graph_str[:800],
        call_chains=call_chains_str[:400],
        summary=summary_str[:1200],
    )

    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))
    try:
        response = client.messages.create(
            model=model_name,
            max_tokens=512,
            system=_JUDGE_SYSTEM,
            messages=[{"role": "user", "content": user_msg}],
        )
        raw = response.content[0].text.strip()
        # Strip markdown fences the model may add despite instructions
        if raw.startswith("```"):
            raw = re.sub(r"^```[a-z]*\n?", "", raw)
            raw = re.sub(r"\n?```$", "", raw.rstrip())
        scores = json.loads(raw)
    except Exception as e:
        scores = {"error": str(e), "overall": -1, "_raw": response.content[0].text[:200] if 'response' in dir() else "no response"}

    return scores


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def _run(cmd: List[str], cwd: Optional[Path] = None, check: bool = True) -> str:
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{r.stderr}")
    return r.stdout.strip()


def clone_at_commit(repo: str, commit: str, cache_dir: Path) -> Path:
    """
    Full clone of `repo`, then hard-reset to `commit`.
    Reuses the existing clone on subsequent calls (just re-checks out the commit).
    Returns the local repo root.
    """
    slug = repo.replace("/", "__")
    dest = cache_dir / slug

    if dest.exists():
        current = _run(["git", "rev-parse", "HEAD"], cwd=dest, check=False)
        if current.startswith(commit[:8]):
            print(f"  [cache hit] {repo}@{commit[:8]}")
            return dest
        print(f"  [updating] {repo} → {commit[:8]}")
        _run(["git", "fetch", "origin"], cwd=dest, check=False)
        _run(["git", "checkout", "--detach", commit], cwd=dest, check=False)
        return dest

    print(f"  [cloning] https://github.com/{repo} @ {commit[:8]}")
    _run([
        "git", "clone",
        f"https://github.com/{repo}.git",
        str(dest),
    ])
    # Checkout the exact base commit
    current = _run(["git", "rev-parse", "HEAD"], cwd=dest, check=False)
    if not current.startswith(commit[:8]):
        _run(["git", "checkout", "--detach", commit], cwd=dest, check=False)

    return dest


# ---------------------------------------------------------------------------
# Patch parsing helpers
# ---------------------------------------------------------------------------

def extract_patch_files(patch: str) -> List[str]:
    """Return relative paths of files modified by the patch."""
    return re.findall(r"^--- a/(.+)$", patch, re.MULTILINE)


def extract_patch_hunks(patch: str) -> Dict[str, str]:
    """Return {file_path: unified diff lines for that file}."""
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
# File neighbour discovery (import-graph radius expansion)
# ---------------------------------------------------------------------------

def _python_imports(path: Path) -> Set[str]:
    """Best-effort: return module names referenced in a Python file."""
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


def _module_to_file(module: str, repo_root: Path) -> Optional[Path]:
    """Try to resolve a module name to a .py file inside the repo."""
    parts = module.replace(".", "/")
    candidates = [
        repo_root / (parts + ".py"),
        repo_root / parts / "__init__.py",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def collect_neighbourhood(
    epicentre_files: List[Path],
    repo_root: Path,
    radius: int = 1,
    max_files: int = 30,
) -> List[Path]:
    """
    BFS expansion from `epicentre_files` through import edges.
    Returns at most `max_files` files (epicentre always included).
    """
    visited: Set[Path] = set(epicentre_files)
    frontier: Set[Path] = set(epicentre_files)

    for _ in range(radius):
        next_frontier: Set[Path] = set()
        for f in frontier:
            if not f.exists():
                continue
            for mod in _python_imports(f):
                neighbour = _module_to_file(mod, repo_root)
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
# Per-instance runner
# ---------------------------------------------------------------------------

def run_instance(
    instance: Dict,
    model_name: str,
    radius: int,
    max_files: int,
    out_dir: Path,
    cache_dir: Path,
    agent_executor,
) -> Dict:
    instance_id  = instance["instance_id"]
    repo         = instance["repo"]
    base_commit  = instance["base_commit"]
    problem      = instance["problem_statement"]
    patch        = instance["patch"]

    print(f"\n{'='*60}")
    print(f"Instance : {instance_id}")
    print(f"Repo     : {repo}  @  {base_commit[:8]}")

    # Step 1 – clone / update
    try:
        repo_root = clone_at_commit(repo, base_commit, cache_dir)
    except Exception as e:
        return {"instance_id": instance_id, "error": f"clone failed: {e}"}

    # Step 2 – find epicentre files (from patch)
    patch_files  = extract_patch_files(patch)
    patch_diffs  = extract_patch_hunks(patch)
    epi_paths    = [repo_root / f for f in patch_files if (repo_root / f).exists()]

    if not epi_paths:
        print(f"  WARNING: no patch files found on disk, using repo root scan")
        epi_paths = list((repo_root).rglob("*.py"))[:5]

    print(f"  Epicentre: {[str(p.relative_to(repo_root)) for p in epi_paths]}")

    # Step 3 – collect neighbourhood
    all_files = collect_neighbourhood(epi_paths, repo_root, radius=radius, max_files=max_files)
    print(f"  Neighbourhood ({radius}-hop): {len(all_files)} files")

    # Step 4 – build FileInput objects
    file_inputs: List[FileInput] = []
    for p in all_files:
        rel = str(p.relative_to(repo_root))
        try:
            content = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        file_inputs.append(FileInput(path=rel, content=content))

    # Step 5 – craft query grounded in the actual bug
    query = (
        f"The following issue was reported in the {repo} repository:\n\n"
        f"{problem[:600]}\n\n"
        f"The fix touches these files: {patch_files}.\n\n"
        f"Using the provided source files:\n"
        f"1. Build the full dependency graph.\n"
        f"2. Trace all call chains that pass through the patched file(s).\n"
        f"3. Identify entry points and potential root causes based on the architecture.\n"
        f"4. Summarise how the dependency structure relates to the reported bug."
    )

    request = CodeAnalysisRequest(files=file_inputs, query=query)

    # Step 6 – run CAST agent
    print(f"  Running CAST agent with {len(file_inputs)} files...")
    try:
        result: CodeAnalysisResult = run_agent(
            request,
            model_name=model_name,
            agent_executor=agent_executor,
        )
    except Exception as e:
        return {"instance_id": instance_id, "error": f"agent failed: {e}"}

    # Step 7 – build output record
    record = {
        "instance_id"        : instance_id,
        "repo"               : repo,
        "base_commit"        : base_commit,
        "patch_files"        : patch_files,
        "neighbourhood_files": [str(p.relative_to(repo_root)) for p in all_files],
        "files_analysed"     : len(file_inputs),
        "problem_statement"  : problem[:800],
        "patch_diff_summary" : {k: f"({v.count(chr(10))} lines)" for k, v in patch_diffs.items()},
        "cast_result"        : result.model_dump(),
    }

    # Step 8 – LLM-as-judge evaluation
    print(f"  Evaluating with LLM judge ({model_name})...")
    full_patch = "\n".join(patch_diffs.values())
    judge_scores = judge_result(record, full_patch, model_name=model_name)
    record["judge"] = judge_scores
    overall = judge_scores.get("overall", "?")
    fc = "✓" if judge_scores.get("file_correct") else "✗"
    fnc = "✓" if judge_scores.get("function_correct") else "✗"
    print(f"  Judge scores → overall={overall}/5  file={fc}  func={fnc}  "
          f"root_cause={judge_scores.get('root_cause_score','?')}/5  "
          f"fix={judge_scores.get('fix_suggestion_score','?')}/5")

    # Save individual result
    out_path = out_dir / f"{instance_id}.json"
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, ensure_ascii=False)
    print(f"  Saved → {out_path}")

    return record


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Run CAST agent on SWE-bench real repos")
    ap.add_argument("--instances", nargs="+", default=DEFAULT_INSTANCES,
                    help="SWE-bench instance IDs to run (default: 5 curated instances)")
    ap.add_argument("--model",   default="claude-haiku-4-5")
    ap.add_argument("--radius",  type=int, default=1,
                    help="Import-graph BFS radius around patch files (default: 1)")
    ap.add_argument("--max_files", type=int, default=20,
                    help="Max files to pass to the agent per instance (default: 20)")
    ap.add_argument("--out_dir", default=str(RESULTS_DIR))
    ap.add_argument("--cache_dir", default=str(REPO_CACHE_DIR))
    ap.add_argument("--split",   default="test", choices=["test","dev"])
    args = ap.parse_args()

    out_dir   = Path(args.out_dir)
    cache_dir = Path(args.cache_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    # Load SWE-bench
    print("Loading SWE-bench Lite...")
    ds = load_dataset("princeton-nlp/SWE-bench_Lite", split=args.split)
    index = {d["instance_id"]: d for d in ds}

    # Validate requested instances
    missing = [i for i in args.instances if i not in index]
    if missing:
        # Try partial match fallback
        all_ids = list(index.keys())
        resolved = []
        for m in missing:
            matches = [i for i in all_ids if m in i]
            if matches:
                print(f"  Partial match '{m}' → '{matches[0]}'")
                resolved.append(matches[0])
            else:
                print(f"  WARNING: instance '{m}' not found, skipping.")
        args.instances = [i for i in args.instances if i not in missing] + resolved

    # Build agent once (reused across all instances)
    print(f"\nBuilding CAST agent ({args.model})...")
    agent_executor = build_agent(args.model)

    # Run
    all_results = []
    for iid in args.instances:
        instance = index.get(iid)
        if not instance:
            continue
        record = run_instance(
            instance     = instance,
            model_name   = args.model,
            radius       = args.radius,
            max_files    = args.max_files,
            out_dir      = out_dir,
            cache_dir    = cache_dir,
            agent_executor = agent_executor,
        )
        all_results.append(record)

    # Save combined summary
    summary_path = out_dir / "summary.json"
    summary = []
    for r in all_results:
        if "error" in r:
            summary.append({"instance_id": r["instance_id"], "error": r["error"]})
            continue
        cr = r.get("cast_result", {})
        j = r.get("judge", {})
        summary.append({
            "instance_id"         : r["instance_id"],
            "repo"                : r["repo"],
            "patch_files"         : r["patch_files"],
            "files_analysed"      : r["files_analysed"],
            "entry_points"        : cr.get("entry_points", []),
            "cycles"              : cr.get("cycles", []),
            "num_dep_edges"       : sum(len(v) for v in cr.get("dependency_graph", {}).values()),
            "num_call_chains"     : len(cr.get("call_chains", [])),
            "summary_excerpt"     : cr.get("summary", "")[:300],
            "judge_overall"       : j.get("overall", -1),
            "judge_file_correct"  : j.get("file_correct", False),
            "judge_func_correct"  : j.get("function_correct", False),
            "judge_root_cause"    : j.get("root_cause_score", -1),
            "judge_fix"           : j.get("fix_suggestion_score", -1),
            "judge_rationale"     : j.get("rationale", ""),
        })

    with open(summary_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, ensure_ascii=False)

    print(f"\n{'='*60}")
    print(f"Done. Full results in : {out_dir}/")
    print(f"Summary              : {summary_path}")
    print(f"\nSummary table:")
    for s in summary:
        if "error" in s:
            print(f"  ❌ {s['instance_id']} – {s['error']}")
        else:
            fc  = "✓" if s.get("judge_file_correct") else "✗"
            fnc = "✓" if s.get("judge_func_correct") else "✗"
            print(f"  ✓  {s['instance_id']}  |  {s['files_analysed']} files  |"
                  f"  {s['num_dep_edges']} dep-edges  |  {s['num_call_chains']} chains  |"
                  f"  judge={s.get('judge_overall','?')}/5  file={fc}  func={fnc}  "
                  f"root={s.get('judge_root_cause','?')}/5  fix={s.get('judge_fix','?')}/5")


if __name__ == "__main__":
    main()
