"""
generate_smith_dataset.py – Generate synthetic bug dataset using SWE-smith.

Uses SWE-smith's procedural modifiers to inject realistic bugs into popular
Python repositories, producing a CAST-agent-compatible evaluation dataset.

Each generated instance contains:
  - instance_id        unique identifier  (<repo>.<modifier>.<hash>)
  - repo               owner/repo string
  - base_commit        commit hash from the swesmith registry
  - patch              unified diff that *fixes* the injected bug
  - problem_statement  natural-language issue description
  - bug_type           modifier explanation
  - file_path          file containing the bug
  - entity_name        function/class name that was mutated

Usage
-----
    cd DependEval
    export $(grep -v '^#' ../.env | xargs)
    uv run python generate_smith_dataset.py          # default repos, 5 bugs each
    uv run python generate_smith_dataset.py --max_bugs 10 --repos pallets__flask.bc098406
"""

from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

# ── swesmith imports ──────────────────────────────────────────────────────
from swesmith.profiles import registry
from swesmith.bug_gen.procedural.python import MODIFIERS_PYTHON
from swesmith.bug_gen.utils import generate_patch_fast
from swesmith.constants import CodeEntity, BugRewrite

# ── issue generation helpers (adapted from swesmith.issue_gen.get_static) ─
from unidiff import PatchSet

# ---------------------------------------------------------------------------
# Target repos – well-known Python projects registered in swesmith
# ---------------------------------------------------------------------------
DEFAULT_REPOS = [
    "pallets__flask.bc098406",
    "pallets__click.fde47b4b",
    "joke2k__faker.8b401a7d",
    "pallets__jinja.ada0a9a6",
    "marshmallow-code__marshmallow.9716fc62",
]

# ---------------------------------------------------------------------------
# Issue prompt templates (from swesmith issue_gen.get_static, simplified)
# ---------------------------------------------------------------------------
PROMPT_BASIC = (
    "There is a bug in this codebase. Please look into it and resolve the issue."
)
PROMPT_FILES = (
    "There are bug(s) in this codebase, likely located in the following file(s):\n"
    "- {gold_files}\n\n"
    "Please look into them and fix any bugs that you find."
)
PROMPT_FILES_FUNCS = (
    "There are bug(s) in this codebase, likely located in the following file(s):\n"
    "- {gold_files}\n\n"
    "I think these function(s) are relevant to the bug:\n"
    "- {gold_funcs}\n\n"
    "Please look into them and fix any bugs that you find."
)
PROMPT_BUG_TYPE_BASIC = (
    "There is a bug in this codebase. {bug_type}\n"
    "Please look into it and resolve the issue."
)
PROMPT_BUG_TYPE_FILES = (
    "There is a bug in this codebase. {bug_type}\n"
    "It seems to be related to the following file(s):\n"
    "- {gold_files}\n\n"
    "Please look into these files and resolve the issue."
)

PROMPT_POOL = [
    (PROMPT_BASIC, 0.10),
    (PROMPT_FILES, 0.20),
    (PROMPT_FILES_FUNCS, 0.25),
    (PROMPT_BUG_TYPE_BASIC, 0.15),
    (PROMPT_BUG_TYPE_FILES, 0.30),
]


def _make_problem_statement(
    patch_text: str,
    entity_name: str,
    bug_type: str,
) -> str:
    """Pick a random prompt template and fill it in."""
    try:
        gold_files = ", ".join(f.path for f in PatchSet(patch_text.splitlines()))
    except Exception:
        gold_files = "<unknown>"

    ctx = dict(
        gold_files=gold_files,
        gold_funcs=entity_name,
        bug_type=bug_type,
    )
    templates, weights = zip(*PROMPT_POOL)
    tmpl = random.choices(templates, weights=weights, k=1)[0]
    return tmpl.format(**ctx)


# ---------------------------------------------------------------------------
# Core generation
# ---------------------------------------------------------------------------

def generate_for_repo(
    repo_key: str,
    max_bugs: int = 5,
    seed: int = 42,
) -> list[dict[str, Any]]:
    """Generate up to *max_bugs* synthetic bug instances for a single repo."""
    random.seed(seed)
    rp = registry.get(repo_key)
    print(f"\n{'='*60}")
    print(f"Repo: {rp.owner}/{rp.repo}  (commit {rp.commit[:8]})")
    print(f"{'='*60}")

    # Clone the repo — try swesmith mirror first, fall back to direct GitHub clone
    dir_path = rp.repo_name
    cloned = False
    try:
        dir_path, cloned = rp.clone()
        print(f"  Cloned via mirror to: {dir_path}  (fresh={cloned})")
    except ValueError:
        # Mirror doesn't exist — clone directly from GitHub
        if not os.path.exists(dir_path):
            print(f"  Mirror unavailable, cloning from GitHub...")
            subprocess.run(
                ["git", "clone", f"https://github.com/{rp.owner}/{rp.repo}.git", dir_path],
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
            cloned = True
            print(f"  Cloned from GitHub to: {dir_path}")
        else:
            print(f"  Using existing clone: {dir_path}")

    # Extract code entities (use our local clone, not rp.extract_entities which
    # calls rp.clone() internally and may fail without mirror)
    from swesmith.bug_gen.adapters import get_entities_from_file
    entities = []
    for root, _, files in os.walk(dir_path):
        for fname in files:
            # Skip tests
            if fname.lower().startswith("test") or fname.rsplit(".", 1)[0].endswith("test"):
                continue
            dirs = root.split("/")
            if any(x in dirs for x in ["tests", "test", "specs"]):
                continue

            fpath = os.path.join(root, fname)
            ext = Path(fpath).suffix
            if ext not in rp.exts:
                continue
            if ext not in get_entities_from_file:
                continue
            try:
                open(fpath, "r", encoding="utf-8").close()
            except Exception:
                continue
            try:
                get_entities_from_file[ext](entities, fpath, -1)
            except Exception:
                continue

    print(f"  Entities found: {len(entities)}")

    if not entities:
        print("  ⚠ No entities found – skipping repo")
        if cloned:
            shutil.rmtree(dir_path)
        return []

    # Build (entity, modifier) candidate pairs
    candidates: list[tuple[CodeEntity, Any]] = []
    for mod in MODIFIERS_PYTHON:
        for entity in entities:
            if mod.can_change(entity):
                candidates.append((entity, mod))

    random.shuffle(candidates)
    print(f"  Candidate (entity, modifier) pairs: {len(candidates)}")

    instances: list[dict[str, Any]] = []
    seen_patches: set[str] = set()  # deduplicate identical diffs

    for entity, mod in candidates:
        if len(instances) >= max_bugs:
            break

        bug: BugRewrite | None = mod.modify(entity)
        if bug is None:
            continue

        patch = generate_patch_fast(entity, bug, dir_path)
        if not patch or patch in seen_patches:
            continue
        seen_patches.add(patch)

        # Build a unique instance id
        rel_file = os.path.relpath(entity.file_path, dir_path)
        inst_id = (
            f"{rp.owner}__{rp.repo}.{rp.commit[:8]}"
            f".{mod.name}__{bug.get_hash()}"
        )

        problem = _make_problem_statement(patch, entity.name, bug.explanation)

        instances.append(
            {
                "instance_id": inst_id,
                "repo": f"{rp.owner}/{rp.repo}",
                "base_commit": rp.commit,
                "patch": patch,
                "problem_statement": problem,
                "bug_type": bug.explanation,
                "modifier": mod.name,
                "file_path": rel_file,
                "entity_name": entity.name,
            }
        )
        print(
            f"  [{len(instances):>3}/{max_bugs}]  "
            f"{mod.name:40s}  {entity.name:30s}  {rel_file}"
        )

    # Clean up clone only if we made it
    if cloned:
        shutil.rmtree(dir_path, ignore_errors=True)

    print(f"  ✓ Generated {len(instances)} instances for {rp.owner}/{rp.repo}")
    return instances


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic bug dataset using SWE-smith"
    )
    parser.add_argument(
        "--repos",
        nargs="+",
        default=DEFAULT_REPOS,
        help="swesmith repo keys (default: 4 popular repos)",
    )
    parser.add_argument(
        "--max_bugs",
        type=int,
        default=5,
        help="Max bugs to generate per repo (default: 5)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed (default: 42)",
    )
    parser.add_argument(
        "--out",
        type=str,
        default="data/swesmith_dataset.json",
        help="Output JSON path",
    )
    args = parser.parse_args()

    all_instances: list[dict] = []
    t0 = time.time()

    for repo_key in args.repos:
        try:
            insts = generate_for_repo(repo_key, args.max_bugs, args.seed)
            all_instances.extend(insts)
        except Exception as e:
            print(f"  ✗ Error with {repo_key}: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()

    elapsed = time.time() - t0

    # Write output
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(all_instances, f, indent=2)

    print(f"\n{'='*60}")
    print(f"Dataset written to {out_path}")
    print(f"Total instances: {len(all_instances)}")
    print(f"Repos:           {len(args.repos)}")
    print(f"Elapsed:         {elapsed:.1f}s")
    print(f"{'='*60}")

    # Print summary table
    from collections import Counter
    mod_counts = Counter(inst["modifier"] for inst in all_instances)
    repo_counts = Counter(inst["repo"] for inst in all_instances)

    print("\nBy repo:")
    for repo, count in repo_counts.most_common():
        print(f"  {repo:40s}  {count}")
    print("\nBy modifier:")
    for mod, count in mod_counts.most_common():
        print(f"  {mod:40s}  {count}")


if __name__ == "__main__":
    main()
