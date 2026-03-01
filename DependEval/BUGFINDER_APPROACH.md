# BugFinder: Mutation-Aware Bug Detection Agent

A ReAct-based semantic code inspection agent evaluated on [SWE-smith](https://github.com/SWE-bench/SWE-smith) synthetic single-function mutations.

---

## Overview

**BugFinder** is a single-turn ReAct agent designed specifically for **single-function mutation detection**: given the buggy version of a mutated function and a natural-language problem description, the agent:

1. Reads the **buggy function body** injected directly into its query
2. Optionally uses tools to gather additional context (callers, related functions)
3. Identifies the **exact mutation** — what was changed and why it breaks behaviour
4. Produces a **concrete fix** (complete corrected function body, not just a description)
5. Reports structured JSON: `buggy_file`, `buggy_function`, `root_cause_analysis`, `fix_suggestion`, `confidence`, `summary`

The agent is implemented in [`agent_bugfinder.py`](agent_bugfinder.py) and evaluated on synthetic SWE-smith instances using the [`swesmith_bugfinder.py`](swesmith_bugfinder.py) harness.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       swesmith_bugfinder.py                         │
│                                                                     │
│  SWE-smith dataset ──► apply patch  (git apply)                     │
│                     ──► extract buggy function body                 │
│                     ──► extract diff hint (removed lines)           │
│                     ──► revert patch (git apply --reverse)          │
│                     ──► craft query (problem + buggy body + hint)  │
│                     ──► run BugFinder agent                         │
│                     ──► LLM-as-judge  3-way comparison              │
│                     ──► deterministic file/func scoring             │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        agent_bugfinder.py                           │
│                                                                     │
│  BugAnalysisRequest ──► LangGraph ReAct agent (claude-haiku-4-5)   │
│                                                                     │
│  Tools available:                                                   │
│    • list_files       – list loaded file paths                      │
│    • read_file        – read a source file                          │
│    • get_file_outline – AST outline (classes, functions, methods)   │
│    • read_function    – extract one function body by name           │
│    • search_code      – ripgrep / regex search over all files       │
│    • analyze_function – static mutation-pattern analysis            │
│    • run_python       – execute a code snippet in the repo          │
│    • run_tests        – run pytest in the repo                      │
│                                                                     │
│  Output: BugAnalysisResult (structured JSON)                        │
│    • buggy_file, buggy_function                                     │
│    • root_cause_analysis, fix_suggestion                            │
│    • confidence, summary, raw_agent_output                          │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    LLM-as-Judge  (3-way)                            │
│                                                                     │
│  original code  ──┐                                                 │
│  buggy code     ──┼──► claude-haiku-4-5 judge ──► scores JSON      │
│  proposed fix   ──┘                                                 │
│                                                                     │
│  Scores: root_cause (0-5), fix_suggestion (0-5), overall (0-5)     │
│  + judge writes & runs a self-contained test to validate the fix   │
│                                                                     │
│  file_correct / function_correct: computed DETERMINISTICALLY        │
│  (not by the LLM) via _path_matches() and _func_matches()          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Key Design Decisions

### 1. Inject buggy code directly into the query

Rather than asking the agent to navigate to the right file with tool calls, the harness:
1. Applies the mutation patch to a local clone (`git apply`)
2. Reads the mutated file
3. Extracts the exact target function body (`_extract_entity_from_source`)
4. Embeds it inline in the agent query
5. Reverts the patch (`git apply --reverse`) to leave the repo clean

This eliminates the single biggest source of failure in early versions: the agent burning tool calls and recursion budget just *finding* the buggy code.

### 2. Multi-occurrence function extraction

A file can contain multiple definitions with the same name (overload stubs, subclasses). The extractor:
- Collects **all** `def func_name` occurrences in the source
- If `target_line` (from the patch `@@ -a,b +c,d @@` header) is known → picks the occurrence whose line range contains that line
- Otherwise → picks the **longest** occurrence (avoids one-liner `@overload` stubs)

### 3. Deterministic file/function scoring

Previous iterations used the LLM judge to score `file_correct` and `function_correct`, producing inconsistent results. Those fields were removed from the judge schema; the harness computes them deterministically:

- **`_path_matches(predicted, expected_list)`**: normalises `src/`/`lib/` prefixes, splits compound answers (`"flask/app.py or werkzeug/serving.py"`), extracts embedded `.py` paths from prose descriptions.
- **`_func_matches(predicted, expected)`**: strips parenthetical qualifiers (`"callback (nested within version_option)"` → `"callback"`) and module prefixes.

### 4. 3-way judge with executable test

The judge receives:
- **Original** (correct) function body
- **Buggy** (mutated) function body
- **Agent's proposed fix**
- **Ground-truth diff**

It scores root-cause and fix accuracy, and writes a **self-contained Python test** that calls both the original and proposed fix with the same arguments and asserts they match. The harness executes this test and reports `test_passed`.

---

## Pipeline (step by step)

| Step | What happens |
|------|-------------|
| **1. Load instance** | Pull metadata from `data/swesmith_dataset.json`: `instance_id`, `repo`, `patch`, `problem_statement`, `entity_name`, `file_path`, `bug_type` |
| **2. Clone repo** | Resolve swesmith profile + clone/reuse local mirror (`.swesmith_repos/`) |
| **3. Identify epicentre** | Parse `--- a/<file>` headers from patch to find mutated files; fall back to `file_path` field |
| **4. Apply patch → read buggy code** | `git apply` mutation, read patched files into memory, `git apply --reverse` to revert |
| **5. Collect neighbourhood** | BFS over Python import graph from epicentre files; default radius=1, max 5 files |
| **6. Extract entity** | Find target function body in buggy source using patch `@@` line number as the selector |
| **7. Extract diff hint** | Collect `-` / `+` diff lines (max 800 chars) as a compact hint of what changed |
| **8. Craft query** | Problem statement + file/function hints + **buggy function body** + diff hint; agent told to output JSON |
| **9. Run BugFinder agent** | `run_agent()` invokes LangGraph ReAct loop (recursion_limit=80); parses last AI message JSON |
| **10. Judge evaluation** | 3-way LLM judge (original vs buggy vs fix); judge writes & executes a validation test |
| **11. Deterministic scoring** | `_path_matches` / `_func_matches` override `file_correct` / `function_correct` |
| **12. Save results** | Per-instance JSON → `results/swesmith_bugfinder/<id>.json`; cumulative `summary.json` |

---

## Repository Layout

```
DependEval/
├── agent_bugfinder.py        # BugFinder ReAct agent (LangGraph)
├── swesmith_bugfinder.py     # SWE-smith harness + 3-way judge
├── BUGFINDER_APPROACH.md     # This file
├── generate_smith_dataset.py # Build data/swesmith_dataset.json
├── data/
│   └── swesmith_dataset.json # 15 synthetic bug instances
└── results/
    └── swesmith_bugfinder/
        ├── summary.json      # All results in one place
        └── <instance_id>.json
```

---

## Evaluation Design

### What the agent is given (oracle inputs)
- The **problem statement** written for the mutation
- The **buggy function body** (mutated version, extracted from patched file)
- A **diff hint** showing which lines were removed/added
- Neighbourhood source files (import graph, radius=1) with buggy content injected

### What the agent is *not* given
- The clean/original function body
- The ground-truth patch
- Any explicit statement of which mutation type was applied

### LLM-as-Judge rubric (3-way)

The judge sees original + buggy + proposed fix and scores:

| Dimension | Range | What it measures |
|-----------|-------|-----------------|
| `root_cause_score` | 0–5 | How accurately did the agent describe what changed and why? |
| `fix_suggestion_score` | 0–5 | How closely does the proposed fix restore the original? |
| `overall` | 0–5 | Holistic quality of the analysis |
| `test_passed` | true/false/null | Did the judge's self-written validation test pass? |
| `file_correct` | true/false | **Deterministic**: did agent identify correct file? |
| `function_correct` | true/false | **Deterministic**: did agent name correct function? |

**Score rubric (0–5):**
- 0 = wrong/empty
- 1 = vaguely related
- 2 = right direction, wrong details
- 3 = correct area, missing specifics
- 4 = mostly accurate/correct
- 5 = exact match

---

## Results (15-instance pilot)

Run with `--model claude-haiku-4-5 --radius 1 --max_files 10`.

| Instance | Modifier | Entity | File | Func | Root | Fix | Overall |
|---|---|---|:---:|:---:|:---:|:---:|:---:|
| flask · func_pm_ctrl_shuffle | ctrl_shuffle | has_level_handler | ✓ | ✓ | 5/5 | 5/5 | **5/5** |
| flask · func_pm_remove_cond | remove_cond | _validate_key | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| flask · func_pm_remove_assign | remove_assign | get_send_file_max_age | ✓ | ✓ | 5/5 | 5/5 | **5/5** |
| flask · func_pm_op_change | op_change | stream_with_context | ✓ | ✓ | 5/5 | 5/5 | **5/5** |
| flask · func_pm_remove_wrapper | remove_wrapper | run | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| click · func_pm_remove_assign | remove_assign | handle_parse_result | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| click · func_pm_remove_assign | remove_assign | command | ✓ | ✓ | 5/5 | 5/5 | **5/5** |
| click · func_pm_op_swap | op_swap | convert | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| click · func_pm_op_break_chains | op_break_chains | write_dl | ✓ | ✓ | 4/5 | 3/5 | **4/5** |
| click · func_pm_op_change | op_change | callback | ✓ | ✓ | 5/5 | 5/5 | **5/5** |
| faker · func_pm_remove_assign | remove_assign | mac_address | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| faker · func_pm_remove_loop | remove_loop | wrapper | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| faker · func_pm_op_change | op_change | domain_name | ✓ | ✓ | 4/5 | 4/5 | **4/5** |
| faker · func_pm_op_change_const | op_change_const | ssn | ✓ | ✓ | 3/5 | 3/5 | **3/5** |
| faker · func_pm_remove_cond | remove_cond | \__getattribute\__ | ✓ | ✓ | 4/5 | 3/5 | **4/5** |

**Aggregate (15 instances, all scored):**

| Metric | Score |
|--------|-------|
| Mean overall | **4.40 / 5** |
| File localisation | **100%** (15/15) |
| Function localisation | **100%** (15/15) |
| Mean root-cause | ~4.27 / 5 |
| Mean fix suggestion | ~4.13 / 5 |

**Comparison:**

| Agent | Dataset | Overall |
|-------|---------|---------|
| CAST (architecture agent) | SWE-smith (15 inst.) | 0.72 / 5 |
| **BugFinder** | SWE-smith (15 inst.) | **4.40 / 5** |

**Key observations:**
- **Perfect file and function localisation** — injecting the buggy code + hints into the query eliminates navigation failures entirely
- **ctrl_shuffle and op_change** (reordered/changed operators) score highest; the diff hint makes the mutation immediately obvious
- **op_break_chains and remove_cond** are slightly harder — the agent must reason about what a missing condition or chained call *should* do, not just what changed
- **op_change_const / ssn** (constant value mutations in locale-specific code) are hardest: the correct constant requires domain knowledge the model may not have

---

## Quick Start

```bash
# 1. Set your API key
echo "ANTHROPIC_API_KEY=sk-ant-..." > ../.env

# 2. Generate / refresh the dataset (15 instances, 5 per repo)
cd DependEval
uv run python generate_smith_dataset.py --max_bugs 5

# 3. Run the full benchmark
export $(grep -v '^#' ../.env | xargs)
uv run python -W ignore swesmith_bugfinder.py

# 4. Run only 3 instances (quick test)
uv run python -W ignore swesmith_bugfinder.py --max 3

# 5. Re-run a specific instance by substring match
uv run python -W ignore swesmith_bugfinder.py \
    --instance func_pm_ctrl_shuffle

# 6. View the summary table
python -m json.tool results/swesmith_bugfinder/summary.json
```

### CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--dataset` | `data/swesmith_dataset.json` | Path to dataset file |
| `--model` | `claude-haiku-4-5` | Anthropic model for agent + judge |
| `--radius` | `1` | BFS hops for neighbourhood collection |
| `--max_files` | `10` | Maximum files fed to the agent |
| `--max` | `0` (all) | Stop after N instances |
| `--instance` | `""` | Run only instances whose ID contains this substring |
| `--out_dir` | `results/swesmith_bugfinder` | Output directory |

---

## Known Limitations

1. **Oracle inputs** — the harness supplies `entity_name` and `file_path` from the ground-truth dataset record. A real deployment would need to localise the bug first (file- and function-level) before injecting context.

2. **Single-language** — neighbourhood BFS only parses Python `import` statements. Mutations in non-Python files are not collected.

3. **Constant-value mutations** — `op_change_const` mutations (e.g., changing a Canadian SIN format constant) require locale-specific domain knowledge that `claude-haiku-4-5` may lack. A larger model or retrieval step would help here.

4. **Judge reliability** — the self-written test occasionally fails for pure side-effect functions (I/O, state mutation) where constructing an assertion is non-trivial. `test_passed=null` is reported in those cases; scores still reflect qualitative analysis.

5. **Dataset size** — 15 instances across 3 repos (pallets/flask, pallets/click, joke2k/faker). Results may not generalise to all mutation types or codebases.

---

## Extending

### Use a stronger model

```bash
uv run python -W ignore swesmith_bugfinder.py --model claude-sonnet-4-5
```

### Increase neighbourhood depth

```bash
uv run python -W ignore swesmith_bugfinder.py --radius 2 --max_files 15
```

### Add a new repo to the dataset

Edit `generate_smith_dataset.py` — add the swesmith profile key to `REPO_KEYS` and re-run:

```bash
uv run python generate_smith_dataset.py --max_bugs 5
```

### Inspect a specific result

```python
import json
r = json.load(open("results/swesmith_bugfinder/pallets__flask.bc098406.func_pm_ctrl_shuffle__dkpg0rwv.json"))
print(r["bugfinder_result"]["root_cause_analysis"])
print(r["judge"]["rationale"])
```
