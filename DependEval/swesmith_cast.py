"""
swesmith_cast.py – Run the CAST ReAct agent on SWE-smith synthetic bug instances.

This script reads the dataset produced by generate_smith_dataset.py and runs the
CAST agent on each instance, reusing the same LLM-as-judge evaluation pipeline
from swebench_cast.py.

Usage
-----
    cd DependEval
    export $(grep -v '^#' ../.env | xargs)

    # First generate the dataset (if not already done)
    uv run python generate_smith_dataset.py

    # Then run the CAST agent on it
    uv run python swesmith_cast.py
    uv run python swesmith_cast.py --dataset data/swesmith_dataset.json --max 10
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

from agent_cast import (
    CodeAnalysisRequest,
    CodeAnalysisResult,
    build_agent,
    run_agent,
)

from shared import (
    FileInput,
    collect_neighbourhood,
    clone_swesmith_repo,
    extract_patch_files,
    extract_patch_hunks,
)

from swebench_cast import judge_result

RESULTS_DIR = Path("results/swesmith_cast")


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

    # Derive the swesmith repo key from the instance_id
    # Format: owner__repo.commit8.modifier__hash
    parts = inst_id.split(".")
    repo_key = f"{parts[0]}.{parts[1]}"  # e.g. pallets__flask.bc098406

    print(f"\n{'='*60}")
    print(f"Instance : {inst_id}")
    print(f"Repo     : {repo}  |  Bug: {bug_type[:60]}")
    print(f"File     : {file_path}  |  Entity: {entity}")

    # Step 1 – clone
    try:
        repo_root = clone_swesmith_repo(repo_key)
    except Exception as e:
        return {"instance_id": inst_id, "error": f"clone failed: {e}"}

    # Step 2 – find epicentre files (from patch)
    patch_files = extract_patch_files(patch)
    patch_diffs = extract_patch_hunks(patch)
    epi_paths   = [repo_root / f for f in patch_files if (repo_root / f).exists()]

    if not epi_paths:
        # Fallback: use the file_path from the instance
        if file_path:
            fp = repo_root / file_path
            if fp.exists():
                epi_paths = [fp]
        if not epi_paths:
            print(f"  WARNING: no patch files found on disk")
            epi_paths = list(repo_root.rglob("*.py"))[:5]

    print(f"  Epicentre: {[str(p.relative_to(repo_root)) for p in epi_paths]}")

    # Step 3 – collect neighbourhood
    all_files = collect_neighbourhood(epi_paths, repo_root, radius=radius, max_files=max_files)
    print(f"  Neighbourhood ({radius}-hop): {len(all_files)} files")

    # Step 4 – FileInput objects
    file_inputs: List[FileInput] = []
    for p in all_files:
        rel = str(p.relative_to(repo_root))
        try:
            content = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        file_inputs.append(FileInput(path=rel, content=content))

    # Step 5 – craft query
    query = (
        f"The following issue was reported in the {repo} repository:\n\n"
        f"{problem[:800]}\n\n"
        f"Using the provided source files:\n"
        f"1. Build the full dependency graph.\n"
        f"2. Trace all call chains that pass through the affected file(s).\n"
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
        return {"instance_id": inst_id, "error": f"agent failed: {e}"}

    # Step 7 – build output record
    record = {
        "instance_id"        : inst_id,
        "repo"               : repo,
        "base_commit"        : instance.get("base_commit", ""),
        "patch_files"        : patch_files,
        "neighbourhood_files": [str(p.relative_to(repo_root)) for p in all_files],
        "files_analysed"     : len(file_inputs),
        "problem_statement"  : problem[:800],
        "bug_type"           : bug_type,
        "modifier"           : instance.get("modifier", ""),
        "entity_name"        : entity,
        "patch_diff_summary" : {k: f"({v.count(chr(10))} lines)" for k, v in patch_diffs.items()},
        "cast_result"        : result.model_dump(),
    }

    # Step 8 – LLM-as-judge evaluation
    print(f"  Evaluating with LLM judge ({model_name})...")
    full_patch = "\n".join(patch_diffs.values())
    judge_scores = judge_result(record, full_patch, model_name=model_name)
    record["judge"] = judge_scores
    overall = judge_scores.get("overall", "?")
    fc = "Y" if judge_scores.get("file_correct") else "N"
    fnc = "Y" if judge_scores.get("function_correct") else "N"
    print(f"  Judge → overall={overall}/5  file={fc}  func={fnc}  "
          f"root_cause={judge_scores.get('root_cause_score','?')}/5  "
          f"fix={judge_scores.get('fix_suggestion_score','?')}/5")

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
    ap = argparse.ArgumentParser(description="Run CAST agent on SWE-smith synthetic bugs")
    ap.add_argument("--dataset", default="data/swesmith_dataset.json",
                    help="Path to the swesmith dataset JSON")
    ap.add_argument("--model", default="claude-haiku-4-5")
    ap.add_argument("--radius", type=int, default=1,
                    help="Import-graph BFS radius (default: 1)")
    ap.add_argument("--max_files", type=int, default=20,
                    help="Max files per instance (default: 20)")
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

    # Build agent once
    print(f"\nBuilding CAST agent ({args.model})...")
    agent_executor = build_agent(args.model)

    # Run all instances
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
        cr = r.get("cast_result", {})
        j  = r.get("judge", {})
        summary.append({
            "instance_id"         : r["instance_id"],
            "repo"                : r["repo"],
            "modifier"            : r.get("modifier", ""),
            "entity_name"         : r.get("entity_name", ""),
            "bug_type"            : r.get("bug_type", ""),
            "patch_files"         : r["patch_files"],
            "files_analysed"      : r["files_analysed"],
            "num_dep_edges"       : sum(len(v) for v in cr.get("dependency_graph", {}).values()),
            "num_call_chains"     : len(cr.get("call_chains", [])),
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
    print(f"Summary:          {summary_path}")
    print(f"\nResults by instance:")
    for s in summary:
        if "error" in s:
            print(f"  X {s['instance_id'][:50]:<50s}  ERROR: {s['error'][:40]}")
        else:
            fc  = "Y" if s.get("judge_file_correct") else "N"
            fnc = "Y" if s.get("judge_func_correct") else "N"
            mod = s.get("modifier", "?")[:25]
            print(f"  + {s['instance_id'][:50]:<50s}  "
                  f"judge={s.get('judge_overall','?')}/5  "
                  f"file={fc}  func={fnc}  "
                  f"root={s.get('judge_root_cause','?')}/5  "
                  f"mod={mod}")

    # Aggregate stats
    scored = [s for s in summary if "error" not in s and s.get("judge_overall", -1) >= 0]
    if scored:
        from collections import Counter
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
        mod_scores = {}
        for s in scored:
            mod = s.get("modifier", "unknown")
            mod_scores.setdefault(mod, []).append(s["judge_overall"])
        print(f"\n  By modifier type:")
        for mod, scores in sorted(mod_scores.items()):
            avg = sum(scores) / len(scores)
            print(f"    {mod:40s}  n={len(scores):2d}  avg={avg:.2f}/5")

        # Breakdown by repo
        repo_scores = {}
        for s in scored:
            r = s.get("repo", "unknown")
            repo_scores.setdefault(r, []).append(s["judge_overall"])
        print(f"\n  By repo:")
        for r, scores in sorted(repo_scores.items()):
            avg = sum(scores) / len(scores)
            print(f"    {r:40s}  n={len(scores):2d}  avg={avg:.2f}/5")


if __name__ == "__main__":
    main()
