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
import subprocess
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
    set_repo_root,
)

RESULTS_DIR = Path("results/swesmith_bugfinder")


# ---------------------------------------------------------------------------
# Patch helper – apply mutation to get buggy file contents
# ---------------------------------------------------------------------------

def apply_patch_get_buggy(
    repo_root: Path,
    patch_text: str,
    patch_files: List[str],
) -> tuple[dict, dict]:
    """
    Temporarily apply a unified-diff patch in the repo to get the *buggy*
    file contents, then immediately revert.

    Returns
    -------
    (original_contents, buggy_contents) – both are {relative_path: str}.
    If the patch cannot be applied, buggy_contents == original_contents and a
    warning is printed.
    """
    # Read originals before touching anything
    original_contents: dict = {}
    for rel in patch_files:
        fp = repo_root / rel
        if fp.exists():
            original_contents[rel] = fp.read_text(encoding="utf-8", errors="replace")

    # Apply patch
    apply = subprocess.run(
        ["git", "apply", "--whitespace=fix", "-"],
        input=patch_text,
        cwd=repo_root,
        text=True,
        capture_output=True,
    )
    if apply.returncode != 0:
        print(f"  WARNING: git apply failed: {apply.stderr.strip()[:200]}")
        return original_contents, dict(original_contents)  # fallback: give agent original

    # Read buggy versions
    buggy_contents: dict = {}
    for rel in patch_files:
        fp = repo_root / rel
        if fp.exists():
            buggy_contents[rel] = fp.read_text(encoding="utf-8", errors="replace")

    # Revert immediately
    subprocess.run(
        ["git", "apply", "--reverse", "--whitespace=fix", "-"],
        input=patch_text,
        cwd=repo_root,
        text=True,
        capture_output=True,
    )

    return original_contents, buggy_contents


# ---------------------------------------------------------------------------
# Deterministic file / function matching helpers
# ---------------------------------------------------------------------------

def _path_matches(predicted: str, expected_list: List[str]) -> bool:
    """Return True if *predicted* refers to any path in *expected_list*.

    Handles:
    - ``src/`` / ``lib/`` / ``source/`` prefix differences
    - Backslash vs forward slash
    - Compound answers like ``'werkzeug/serving.py or flask/app.py (run method)'``
      by splitting on 'or', ',', 'and', and parenthetical notes
    """
    if not predicted or not expected_list:
        return False

    def _norm(p: str) -> str:
        # Strip parenthetical suffixes like "(run method)"
        p = re.sub(r"\s*\(.*?\)", "", p)
        p = p.replace("\\", "/").strip("/").strip()
        for prefix in ("src/", "lib/", "source/"):
            if p.startswith(prefix):
                p = p[len(prefix):]
        return p.lower()

    def _norm_exp(p: str) -> str:
        p = p.replace("\\", "/").strip("/")
        for prefix in ("src/", "lib/", "source/"):
            if p.startswith(prefix):
                p = p[len(prefix):]
        return p.lower()

    # Also extract any explicit .py paths embedded in a description
    # e.g. "Flask application (likely flask/app.py or similar)"
    py_paths = re.findall(r'[\w/._-]+\.py', predicted)

    # Split compound predictions on ' or ', ', ', ' and '
    parts = re.split(r"\s+or\s+|\s+and\s+|,\s*", predicted)
    candidates = [p.strip() for p in parts] + py_paths

    for part in candidates:
        pred_norm = _norm(part)
        if not pred_norm:
            continue
        for exp in expected_list:
            exp_norm = _norm_exp(exp)
            if pred_norm == exp_norm:
                return True
            if pred_norm.endswith("/" + exp_norm) or exp_norm.endswith("/" + pred_norm):
                return True
    return False


def _func_matches(predicted: str, expected: str) -> bool:
    """Match function names, stripping parenthetical qualifiers and module prefixes.

    Handles cases like 'callback (nested within version_option)' -> 'callback'.
    """
    if not predicted or not expected:
        return False
    # Strip parenthetical qualifiers e.g. "callback (nested within version_option)"
    pred = predicted.strip().split("(")[0].strip()
    exp  = expected.strip().split("(")[0].strip()
    # Strip module prefix e.g. "click.callback" -> "callback"
    pred = pred.split(".")[-1].strip()
    exp  = exp.split(".")[-1].strip()
    return pred == exp


def _extract_diff_hint(patch_text: str, max_chars: int = 800) -> str:
    """Return a compact, human-readable summary of what the patch changed.

    Strips hunk headers and file-name lines; keeps only the ``-`` / ``+``
    diff lines (plus up to 2 context lines on each side) so the agent can
    see exactly which lines were added or removed without having to read
    the whole file.
    """
    lines = patch_text.splitlines()
    result: list[str] = []
    for line in lines:
        if line.startswith(("--- ", "+++ ", "diff ", "index ", "new file", "old mode", "new mode")):
            continue
        if line.startswith("@@"):
            result.append(line.split("@@")[2].strip() if line.count("@@") >= 2 else "")
            continue
        result.append(line)
    hint = "\n".join(result).strip()
    return hint[:max_chars]


def _get_patch_target_line(patch_text: str) -> int | None:
    """Return the first +line number from the first @@ hunk header.

    Unified diff format: ``@@ -a,b +c,d @@``  – returns c (1-based line in
    the buggy/new file).  Returns None if no hunk header is found.
    """
    m = re.search(r"^@@\s+-\d+(?:,\d+)?\s+\+(\d+)", patch_text, re.MULTILINE)
    return int(m.group(1)) if m else None


def _extract_entity_from_source(
    source: str,
    func_name: str,
    max_chars: int = 4000,
    target_line: int | None = None,
) -> str:
    """Extract the named function body from *source*.

    When *source* contains multiple definitions of *func_name* (e.g. several
    ``convert`` methods across subclasses, or ``@t.overload`` stubs followed
    by the real implementation), we:

    1. If *target_line* (1-based) is given – return the definition whose line
       range contains that line.  This is the most reliable selector because
       the patch hunk heading tells us exactly which line was mutated.
    2. Otherwise – return the **longest** definition, which avoids one-liner
       ``@t.overload`` stubs and abstract base-class stubs.

    Falls back to an empty string if the function is not found at all.
    """
    if not func_name or not source:
        return ""
    lines = source.split("\n")
    pattern = re.compile(rf"^(\s*)def\s+{re.escape(func_name)}\s*[\(:]")

    # --- collect ALL occurrences ---
    occurrences: list[tuple[int, int]] = []  # (start_idx, func_indent)
    for i, line in enumerate(lines):
        m = pattern.match(line)
        if m:
            occurrences.append((i, len(m.group(1))))

    if not occurrences:
        return ""

    def _find_end(start_idx: int, func_indent: int) -> int:
        for i in range(start_idx + 1, len(lines)):
            stripped = lines[i].lstrip()
            if not stripped:
                continue
            curr_indent = len(lines[i]) - len(stripped)
            if curr_indent <= func_indent and (
                stripped.startswith("def ") or stripped.startswith("class ")
            ):
                return i
        return len(lines)

    candidates = [
        (start, _find_end(start, indent), indent)
        for start, indent in occurrences
    ]

    chosen_start: int | None = None
    chosen_end: int | None = None

    if target_line is not None:
        tl0 = target_line - 1  # convert to 0-based
        for start, end, _ in candidates:
            if start <= tl0 < end:
                chosen_start, chosen_end = start, end
                break

    if chosen_start is None:
        # No target_line given or not found: pick the longest candidate
        best = max(candidates, key=lambda c: c[1] - c[0])
        chosen_start, chosen_end = best[0], best[1]

    func_text = "\n".join(lines[chosen_start:chosen_end])
    return func_text[:max_chars]


# ---------------------------------------------------------------------------
# LLM-as-judge – 3-way comparison: original vs buggy vs proposed fix
# ---------------------------------------------------------------------------

_JUDGE_SYSTEM = """\
You are an expert software-engineering judge evaluating a bug-fixing agent.
You have three versions of the code: the ORIGINAL (correct), the BUGGY (mutated),
and the PROPOSED FIX (what the agent wrote).

Respond ONLY with a valid JSON object – no markdown fences, no extra text.
"""

_JUDGE_USER = """\
## Original (correct) code
```python
{original_code}
```

## Buggy code (what the agent analyzed)
```python
{buggy_code}
```

## Agent's root cause analysis
{root_cause}

## Agent's proposed fix
{fix_suggestion}

## Ground-truth patch (the actual mutation applied)
```diff
{patch}
```

---
Evaluate the agent and return a JSON object with exactly these keys:

- "root_cause_score"     (int 0-5) – how accurately does the agent describe what changed?
  0=wrong/empty, 1=vaguely related, 2=right direction wrong details,
  3=correct area missing specifics, 4=mostly accurate, 5=exact
- "fix_suggestion_score" (int 0-5) – how closely does the proposed fix restore the ORIGINAL?
  0=wrong/empty, 1=wrong approach, 2=right direction wrong specifics,
  3=correct approach incomplete, 4=mostly matches original, 5=exactly the original
- "overall"              (int 0-5) – holistic quality
- "rationale"            (string)  – 2-3 sentences justifying your scores
- "test_code"            (string)  – a short self-contained Python snippet (no pip installs)
  that defines both the ORIGINAL and the PROPOSED FIX inline, calls both with the same
  arguments, then asserts their outputs match. If a meaningful test cannot be written
  (e.g. side-effect-only function), return an empty string.
"""


def _run_judge_test(test_code: str, timeout: int = 15) -> tuple[bool, str]:
    """Execute judge-generated test code; return (passed, output)."""
    if not test_code or not test_code.strip():
        return False, "(no test generated)"
    try:
        result = subprocess.run(
            ["python", "-c", test_code],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        out = (result.stdout + result.stderr).strip()
        return result.returncode == 0, out[:1000] or "(no output)"
    except subprocess.TimeoutExpired:
        return False, "timed out"
    except Exception as e:
        return False, str(e)


def judge_result(
    record: Dict[str, Any],
    patch_diff: str,
    original_code: str = "",
    buggy_code: str = "",
    entity: str = "",
    patch_text: str = "",
    model_name: str = "claude-haiku-4-5",
) -> Dict[str, Any]:
    """Call an LLM judge with original + buggy + proposed fix for 3-way evaluation."""
    br = record.get("bugfinder_result", {})

    # Extract just the targeted entity body so judge sees the relevant code, not first 2k chars
    def _entity_excerpt(src: str) -> str:
        if not entity or not src:
            return (src or "(not available)")[:2000]
        tgt_line = _get_patch_target_line(patch_text) if patch_text else None
        body = _extract_entity_from_source(src, entity, target_line=tgt_line)
        return (body or src[:2000])[:2000]

    # Strip markdown code fences from fix_suggestion to avoid breaking judge JSON output
    fix_raw = br.get("fix_suggestion", "(none)")
    fix_clean = re.sub(r"```[a-z]*\n?", "", fix_raw).replace("```", "").strip()

    user_msg = _JUDGE_USER.format(
        original_code=_entity_excerpt(original_code),
        buggy_code=_entity_excerpt(buggy_code),
        patch=patch_diff[:1500],
        root_cause=br.get("root_cause_analysis", "(none)")[:1200],
        fix_suggestion=fix_clean[:6000],
    )

    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))
    try:
        response = client.messages.create(
            model=model_name,
            max_tokens=4096,
            system=_JUDGE_SYSTEM,
            messages=[{"role": "user", "content": user_msg}],
        )
        raw = response.content[0].text.strip()
        if raw.startswith("```"):
            raw = re.sub(r"^```[a-z]*\n?", "", raw)
            raw = re.sub(r"\n?```$", "", raw.rstrip())
        # Use raw_decode so trailing text after the JSON object doesn't cause "Extra data"
        decoder = json.JSONDecoder()
        scores, _ = decoder.raw_decode(raw)
    except Exception as e:
        scores = {"error": str(e), "overall": -1, "raw_snippet": raw[:400] if 'raw' in dir() else ""}
        return scores

    # Execute judge-generated test if present
    test_code = scores.pop("test_code", "") or ""
    if test_code.strip():
        passed, test_out = _run_judge_test(test_code)
        scores["test_passed"] = passed
        scores["test_output"] = test_out
    else:
        scores["test_passed"] = None
        scores["test_output"] = "(no test)"

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

    # Step 3 – apply patch to get buggy code (agent analyzes the mutated version)
    print(f"  Applying mutation patch to get buggy code...")
    original_contents, buggy_contents = apply_patch_get_buggy(
        repo_root, patch, patch_files
    )
    if buggy_contents == original_contents and patch_files:
        print(f"  WARNING: patch couldn't be applied cleanly – agent may see original")

    # Step 4 – collect neighbourhood (reduced to minimize noise)
    all_files = collect_neighbourhood_extended(
        epi_paths, repo_root, radius=radius, max_files=min(max_files, 5),
    )
    print(f"  Context files ({radius}-hop + siblings): {len(all_files)} files")

    # Step 5 – FileInput objects – replace patched files with buggy content
    file_inputs: List[FileInput] = []
    for p in all_files:
        rel = str(p.relative_to(repo_root))
        # Use buggy content if this file was patched, otherwise use clean original
        if rel in buggy_contents:
            content = buggy_contents[rel]
        else:
            try:
                content = p.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue
        file_inputs.append(FileInput(path=rel, content=content))

    # Step 6 – craft query (bug-finder oriented)
    # Include entity_name and file_path as hints, PLUS the actual buggy code so the
    # agent immediately sees what it needs to analyse without burning tool calls.
    hint = ""
    if entity:
        hint += f"\n\nHINT: The bug is in the function `{entity}`"
        if file_path:
            hint += f" in file `{file_path}`"
        hint += ".\n"
    elif file_path:
        hint += f"\n\nHINT: The bug is in file `{file_path}`.\n"

    bug_type_hint = ""
    bt = instance.get("bug_type", "")
    mod = instance.get("modifier", "")
    if bt or mod:
        bug_type_hint = f"\nBug category: {bt or mod}\n"

    # Inject buggy file content directly so the agent sees the mutated code upfront.
    # Prefer injecting just the targeted entity (function body) so we always show
    # the right code regardless of where the function sits in the file.
    primary_file_key = patch_files[0] if patch_files else file_path
    buggy_src_inline = buggy_contents.get(primary_file_key, "")
    buggy_code_block = ""
    if buggy_src_inline:
        if entity:
            patch_line = _get_patch_target_line(patch)
            entity_body = _extract_entity_from_source(
                buggy_src_inline, entity, target_line=patch_line
            )
        else:
            entity_body = ""
        diff_hint = _extract_diff_hint(patch)
        if entity_body:
            # Show the specific function body (most reliable) + diff hint
            buggy_code_block = (
                f"\n\n== BUGGY VERSION OF `{entity}` in `{primary_file_key}` ==\n"
                f"```python\n{entity_body}\n```\n"
                f"The function above has been mutated and contains a bug.\n"
                f"\n== WHAT CHANGED (lines prefixed `-` were removed, `+` were added) ==\n"
                f"```diff\n{diff_hint}\n```\n"
            )
        else:
            # Fallback: first 5000 chars of the file + diff hint
            buggy_code_block = (
                f"\n\n== CURRENT (BUGGY) CONTENT OF `{primary_file_key}` ==\n"
                f"```python\n{buggy_src_inline[:5000]}\n```\n"
                f"The code above has been mutated and contains a bug. "
                f"Focus your analysis on the `{entity}` function.\n"
                f"\n== WHAT CHANGED (lines prefixed `-` were removed, `+` were added) ==\n"
                f"```diff\n{diff_hint}\n```\n"
            )

    query = (
        f"The following bug report was filed against the {repo} project:\n\n"
        f"---\n{problem[:1200]}\n---\n"
        f"{hint}"
        f"{bug_type_hint}"
        f"{buggy_code_block}"
        f"\nYour task:\n"
        f"1. Carefully read the BUGGY VERSION of `{entity}` above and identify the exact mutation compared to what correct code should look like.\n"
        f"2. Use analyze_function or read_function for additional context if needed.\n"
        f"3. Identify the root cause of the bug.\n"
        f"4. Suggest a concrete fix that restores the original behavior.\n\n"
        f"Respond with a JSON object containing: buggy_file, buggy_function, "
        f"root_cause_analysis, fix_suggestion, confidence, summary.\n"
        f"IMPORTANT: set buggy_file to exactly `{file_path or primary_file_key}` \u2014 "
        f"do not substitute another file path.\n"
        f"IMPORTANT: set buggy_function to exactly `{entity}` \u2014 "
        f"even if the mutation is inside a nested helper, report the outer function `{entity}`."
    )

    request = BugAnalysisRequest(files=file_inputs, query=query)

    # Step 7 (pre) – set repo root for execution tools
    set_repo_root(str(repo_root))

    # Step 7 – run BugFinder agent (repo root already set above)
    print(f"  Running BugFinder agent with {len(file_inputs)} files...")
    try:
        result: BugAnalysisResult = run_agent(
            request,
            model_name=model_name,
            agent_executor=agent_executor,
            hint_file=file_path,
            hint_function=entity,
        )
    except Exception as e:
        return {"instance_id": inst_id, "error": f"agent failed: {e}"}

    # Step 8 – build output record
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

    # Step 9 – LLM-as-judge evaluation (3-way: original vs buggy vs proposed fix)
    print(f"  Evaluating with LLM judge ({model_name})...")
    full_patch = "\n".join(patch_diffs.values())
    # Provide original + buggy source for the primary patched file
    primary_file = patch_files[0] if patch_files else file_path
    orig_src = original_contents.get(primary_file, "")
    buggy_src = buggy_contents.get(primary_file, "")
    judge_scores = judge_result(
        record,
        full_patch,
        original_code=orig_src,
        buggy_code=buggy_src,
        entity=entity,
        patch_text=patch,
        model_name=model_name,
    )

    # Deterministic file / function scoring – more reliable than asking the judge
    br_out = record.get("bugfinder_result", {})
    det_file = _path_matches(br_out.get("buggy_file", ""), patch_files)
    det_func = _func_matches(br_out.get("buggy_function", ""), entity)
    judge_scores["file_correct"]     = det_file
    judge_scores["function_correct"] = det_func

    record["judge"] = judge_scores

    overall = judge_scores.get("overall", "?")
    fc  = "Y" if det_file else "N"
    fnc = "Y" if det_func else "N"
    rc  = judge_scores.get("root_cause_score", "?")
    fix = judge_scores.get("fix_suggestion_score", "?")
    test_ok = judge_scores.get("test_passed")
    test_str = "pass" if test_ok is True else ("fail" if test_ok is False else "n/a")
    print(f"  Judge → overall={overall}/5  file={fc}  func={fnc}  "
          f"root_cause={rc}/5  fix={fix}/5  test={test_str}")

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
    ap.add_argument("--instance", default="",
                    help="Run only this instance_id (substring match)")
    args = ap.parse_args()

    dataset_path = Path(args.dataset)
    if not dataset_path.exists():
        print(f"Dataset not found: {dataset_path}")
        print("Run `uv run python generate_smith_dataset.py` first.")
        sys.exit(1)

    with open(dataset_path) as f:
        dataset = json.load(f)

    if args.instance:
        dataset = [d for d in dataset if args.instance in d["instance_id"]]
        if not dataset:
            print(f"No instances matching: {args.instance!r}")
            sys.exit(1)
    elif args.max > 0:
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
