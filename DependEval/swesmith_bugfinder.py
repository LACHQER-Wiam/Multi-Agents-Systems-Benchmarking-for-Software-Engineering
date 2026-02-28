"""
swesmith_bugfinder.py – Run the BugFinder ReAct agent on SWE-smith synthetic bugs.

Unlike swesmith_cast.py (which runs the architecture-focused CAST agent), this
harness uses the BugFinder agent that is purpose-built for single-file bug
detection: semantic code inspection, function-level analysis, root-cause
identification, and fix suggestions.

Usage
-----
    cd DependEval
    export ANTHROPIC_API_KEY=...

    # Run on 5 instances (default)
    uv run python swesmith_bugfinder.py --max 5

    # Run on full dataset
    uv run python swesmith_bugfinder.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List

import anthropic

from agent_bugfinder import (
    BugAnalysisRequest,
    BugAnalysisResult,
    build_agent,
    run_agent,
)

from shared import (
    FileInput,
    clone_swesmith_repo,
    collect_neighbourhood_extended,
    extract_patch_files,
    extract_patch_hunks,
)

RESULTS_DIR = Path("results/swesmith_bugfinder")


# ---------------------------------------------------------------------------
# LLM-as-judge – adapted for the BugFinder output schema
# ---------------------------------------------------------------------------

_JUDGE_SYSTEM = """\
You are an expert software-engineering judge. Your task is to evaluate how well
a bug-finding agent identified and explained a bug, given the actual ground-truth patch.

Respond ONLY with a valid JSON object – no markdown fences, no extra text.
"""

_JUDGE_USER = """\
## Problem statement (what the user reported)
{problem}

## Ground-truth patch (the actual fix committed)
```diff
{patch}
```

## Agent analysis
### Identified buggy file
{buggy_file}

### Identified buggy function
{buggy_function}

### Root cause analysis
{root_cause}

### Fix suggestion
{fix_suggestion}

### Agent summary
{summary}

---
Score the agent analysis on the following criteria and return a JSON object with
exactly these keys:

- "file_correct"        (bool)   – did the agent identify the correct file being patched?
- "function_correct"    (bool)   – did the agent identify the correct function actually changed in the patch?
- "root_cause_score"    (int 0-5) – how accurately does the agent describe the root cause?
  0=completely wrong or empty, 1=vaguely related, 2=partially correct direction,
  3=correct general area but missing details, 4=mostly accurate, 5=exact match
- "fix_suggestion_score" (int 0-5) – how close is the agent's suggested fix to the actual patch?
  0=no fix or completely wrong, 1=wrong approach, 2=right direction but wrong specifics,
  3=correct approach but incomplete, 4=mostly matches patch, 5=exactly the patch
- "overall"             (int 0-5) – holistic quality of the bug analysis
- "rationale"           (string)  – 2-3 sentences justifying your scores
"""


def judge_result(
    record: Dict[str, Any],
    patch_diff: str,
    model_name: str = "claude-haiku-4-5",
) -> Dict[str, Any]:
    """Call an LLM judge to score the BugFinder agent's analysis."""
    br = record.get("bugfinder_result", {})

    user_msg = _JUDGE_USER.format(
        problem=record.get("problem_statement", "")[:800],
        patch=patch_diff[:2000],
        buggy_file=br.get("buggy_file", "(none)"),
        buggy_function=br.get("buggy_function", "(none)"),
        root_cause=br.get("root_cause_analysis", "(none)")[:1200],
        fix_suggestion=br.get("fix_suggestion", "(none)")[:1200],
        summary=br.get("summary", "(none)")[:600],
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
        if raw.startswith("```"):
            raw = re.sub(r"^```[a-z]*\n?", "", raw)
            raw = re.sub(r"\n?```$", "", raw.rstrip())
        scores = json.loads(raw)
    except Exception as e:
        scores = {
            "error": str(e),
            "overall": -1,
        }

    return scores


# ---------------------------------------------------------------------------
# Per-instance runner
# ---------------------------------------------------------------------------

def run_instance(
    instance: Dict[str, Any],
    model_name: str,
    radius: int,
    max_files: int,
    out_dir: Path,
    agent_executor,
) -> Dict[str, Any]:
    inst_id   = instance["instance_id"]
    repo      = instance["repo"]
    patch     = instance["patch"]
    problem   = instance["problem_statement"]
    bug_type  = instance.get("bug_type", "")
    file_path = instance.get("file_path", "")
    entity    = instance.get("entity_name", "")

    # Derive swesmith repo key
    parts = inst_id.split(".")
    repo_key = f"{parts[0]}.{parts[1]}"

    print(f"\n{'='*60}")
    print(f"Instance : {inst_id}")
    print(f"Repo     : {repo}  |  Bug: {bug_type[:60]}")
    print(f"File     : {file_path}  |  Entity: {entity}")

    # Step 1 – clone
    try:
        repo_root = clone_swesmith_repo(repo_key)
    except Exception as e:
        return {"instance_id": inst_id, "error": f"clone failed: {e}"}

    # Step 2 – epicentre
    patch_files = extract_patch_files(patch)
    patch_diffs = extract_patch_hunks(patch)
    epi_paths   = [repo_root / f for f in patch_files if (repo_root / f).exists()]

    if not epi_paths and file_path:
        fp = repo_root / file_path
        if fp.exists():
            epi_paths = [fp]

    if not epi_paths:
        print(f"  WARNING: no patch files found")
        epi_paths = list(repo_root.rglob("*.py"))[:3]

    print(f"  Epicentre: {[str(p.relative_to(repo_root)) for p in epi_paths]}")

    # Step 3 – collect neighbourhood (reduced to minimize noise)
    all_files = collect_neighbourhood_extended(
        epi_paths, repo_root, radius=radius, max_files=min(max_files, 5),
    )
    print(f"  Context files ({radius}-hop + siblings): {len(all_files)} files")

    # Step 4 – FileInput objects
    file_inputs: List[FileInput] = []
    for p in all_files:
        rel = str(p.relative_to(repo_root))
        try:
            content = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        file_inputs.append(FileInput(path=rel, content=content))

    # Step 5 – craft query (bug-finder oriented)
    # Include entity_name and file_path as hints so the agent targets
    # the right function instead of guessing.
    hint = ""
    if entity:
        hint += f"\n\nHINT: The bug is strongly suspected to be in the function `{entity}`"
        if file_path:
            hint += f" in file `{file_path}`"
        hint += ".\n"
    elif file_path:
        hint += f"\n\nHINT: The bug is strongly suspected to be in file `{file_path}`.\n"

    bug_type_hint = ""
    bt = instance.get("bug_type", "")
    mod = instance.get("modifier", "")
    if bt or mod:
        bug_type_hint = f"\nBug category: {bt or mod}\n"

    query = (
        f"The following bug report was filed against the {repo} project:\n\n"
        f"---\n{problem[:1200]}\n---\n"
        f"{hint}"
        f"{bug_type_hint}"
        f"\nYour task:\n"
        f"1. Use read_function on the suspected buggy function to inspect its code.\n"
        f"2. Use analyze_function to check for code anomalies.\n"
        f"3. Identify the root cause of the bug.\n"
        f"4. Suggest a concrete fix.\n\n"
        f"Respond with a JSON object containing: buggy_file, buggy_function, "
        f"root_cause_analysis, fix_suggestion, confidence, summary."
    )

    request = BugAnalysisRequest(files=file_inputs, query=query)

    # Step 6 – run BugFinder agent
    print(f"  Running BugFinder agent with {len(file_inputs)} files...")
    try:
        result: BugAnalysisResult = run_agent(
            request,
            model_name=model_name,
            agent_executor=agent_executor,
        )
    except Exception as e:
        return {"instance_id": inst_id, "error": f"agent failed: {e}"}

    # Step 7 – build output record
    record = {
        "instance_id"        : inst_id,
        "repo"               : repo,
        "base_commit"        : instance.get("base_commit", ""),
        "patch_files"        : patch_files,
        "neighbourhood_files": [str(p.relative_to(repo_root)) for p in all_files],
        "files_analysed"     : len(file_inputs),
        "problem_statement"  : problem[:1200],
        "bug_type"           : bug_type,
        "modifier"           : instance.get("modifier", ""),
        "entity_name"        : entity,
        "patch_diff_summary" : {k: f"({v.count(chr(10))} lines)" for k, v in patch_diffs.items()},
        "bugfinder_result"   : result.model_dump(),
    }

    # Step 8 – LLM-as-judge evaluation
    print(f"  Evaluating with LLM judge ({model_name})...")
    full_patch = "\n".join(patch_diffs.values())
    judge_scores = judge_result(record, full_patch, model_name=model_name)
    record["judge"] = judge_scores

    overall = judge_scores.get("overall", "?")
    fc  = "Y" if judge_scores.get("file_correct") else "N"
    fnc = "Y" if judge_scores.get("function_correct") else "N"
    rc  = judge_scores.get("root_cause_score", "?")
    fix = judge_scores.get("fix_suggestion_score", "?")
    print(f"  Judge → overall={overall}/5  file={fc}  func={fnc}  "
          f"root_cause={rc}/5  fix={fix}/5")

    # Save per-instance result
    safe_id = inst_id.replace("/", "_").replace(":", "_")
    out_path = out_dir / f"{safe_id}.json"
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, ensure_ascii=False)
    print(f"  Saved → {out_path}")

    return record


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Run BugFinder agent on SWE-smith synthetic bugs",
    )
    ap.add_argument("--dataset", default="data/swesmith_dataset.json")
    ap.add_argument("--model", default="claude-haiku-4-5")
    ap.add_argument("--radius", type=int, default=1,
                    help="Import-graph BFS radius (default: 1)")
    ap.add_argument("--max_files", type=int, default=10,
                    help="Max files per instance (default: 10)")
    ap.add_argument("--max", type=int, default=0,
                    help="Max instances to run (0=all)")
    ap.add_argument("--out_dir", default=str(RESULTS_DIR))
    args = ap.parse_args()

    dataset_path = Path(args.dataset)
    if not dataset_path.exists():
        print(f"Dataset not found: {dataset_path}")
        print("Run `uv run python generate_smith_dataset.py` first.")
        sys.exit(1)

    with open(dataset_path) as f:
        dataset = json.load(f)

    if args.max > 0:
        dataset = dataset[:args.max]

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Dataset: {dataset_path} ({len(dataset)} instances)")
    print(f"Model:   {args.model}")
    print(f"Agent:   BugFinder (semantic code inspection)")

    # Build agent once
    print(f"\nBuilding BugFinder agent ({args.model})...")
    agent_executor = build_agent(args.model)

    # Run instances
    all_results: list[dict] = []
    for inst in dataset:
        record = run_instance(
            instance       = inst,
            model_name     = args.model,
            radius         = args.radius,
            max_files      = args.max_files,
            out_dir        = out_dir,
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
        br = r.get("bugfinder_result", {})
        j  = r.get("judge", {})
        summary.append({
            "instance_id"         : r["instance_id"],
            "repo"                : r["repo"],
            "modifier"            : r.get("modifier", ""),
            "entity_name"         : r.get("entity_name", ""),
            "bug_type"            : r.get("bug_type", ""),
            "patch_files"         : r["patch_files"],
            "files_analysed"      : r["files_analysed"],
            "buggy_file_found"    : br.get("buggy_file", ""),
            "buggy_func_found"    : br.get("buggy_function", ""),
            "confidence"          : br.get("confidence", ""),
            "judge_overall"       : j.get("overall", -1),
            "judge_file_correct"  : j.get("file_correct", False),
            "judge_func_correct"  : j.get("function_correct", False),
            "judge_root_cause"    : j.get("root_cause_score", -1),
            "judge_fix"           : j.get("fix_suggestion_score", -1),
            "judge_rationale"     : j.get("rationale", ""),
        })

    with open(summary_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, ensure_ascii=False)

    # Print results table
    print(f"\n{'='*60}")
    print(f"Done. Results in: {out_dir}/")
    print(f"\nResults by instance:")
    for s in summary:
        if "error" in s:
            print(f"  X {s['instance_id'][:50]:<50s}  ERROR")
        else:
            fc  = "Y" if s.get("judge_file_correct") else "N"
            fnc = "Y" if s.get("judge_func_correct") else "N"
            mod = s.get("modifier", "?")[:25]
            print(f"  + {s['instance_id'][:50]:<50s}  "
                  f"overall={s.get('judge_overall','?')}/5  "
                  f"file={fc}  func={fnc}  "
                  f"root={s.get('judge_root_cause','?')}/5  "
                  f"fix={s.get('judge_fix','?')}/5  "
                  f"mod={mod}")

    # Aggregate stats
    scored = [s for s in summary if "error" not in s and s.get("judge_overall", -1) >= 0]
    if scored:
        mean_overall = sum(s["judge_overall"] for s in scored) / len(scored)
        mean_root    = sum(s["judge_root_cause"] for s in scored) / len(scored)
        mean_fix     = sum(s["judge_fix"] for s in scored) / len(scored)
        file_pct     = sum(1 for s in scored if s["judge_file_correct"]) / len(scored) * 100
        func_pct     = sum(1 for s in scored if s["judge_func_correct"]) / len(scored) * 100

        print(f"\nAggregate ({len(scored)} scored instances):")
        print(f"  Mean overall:      {mean_overall:.2f}/5")
        print(f"  Mean root cause:   {mean_root:.2f}/5")
        print(f"  Mean fix score:    {mean_fix:.2f}/5")
        print(f"  File correct:      {file_pct:.0f}%")
        print(f"  Function correct:  {func_pct:.0f}%")

        # Breakdown by modifier
        mod_scores: Dict[str, list] = {}
        for s in scored:
            mod = s.get("modifier", "unknown")
            mod_scores.setdefault(mod, []).append(s["judge_overall"])
        print(f"\n  By modifier type:")
        for mod, scores in sorted(mod_scores.items()):
            avg = sum(scores) / len(scores)
            print(f"    {mod:40s}  n={len(scores):2d}  avg={avg:.2f}/5")

        # Breakdown by repo
        repo_scores: Dict[str, list] = {}
        for s in scored:
            r = s.get("repo", "unknown")
            repo_scores.setdefault(r, []).append(s["judge_overall"])
        print(f"\n  By repo:")
        for r, scores in sorted(repo_scores.items()):
            avg = sum(scores) / len(scores)
            print(f"    {r:40s}  n={len(scores):2d}  avg={avg:.2f}/5")

        # Comparison note
        print(f"\n  ── Comparison with CAST agent ──")
        print(f"  CAST on SWE-smith:       0.72/5 overall (25 instances)")
        print(f"  BugFinder on SWE-smith:  {mean_overall:.2f}/5 overall ({len(scored)} instances)")


if __name__ == "__main__":
    main()
