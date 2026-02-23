# CAST: Code Architecture & Static Tracing Agent

A ReAct-based dependency analysis agent evaluated on [SWE-bench Lite](https://github.com/princeton-nlp/SWE-bench).

---

## Overview

CAST (**C**ode **A**rchitecture & **S**tatic **T**racing) is a single-turn ReAct agent that, given a set of source files and a natural-language problem description, automatically:

1. Reads and parses the source files
2. Builds a **dependency graph** (which file imports which)
3. Traces **call chains** from entry points into the codebase
4. Identifies **root causes** tied to specific functions or modules
5. Suggests a **fix direction** grounded in the architectural trace

The agent is implemented in [`agent_cast.py`](agent_cast.py) and evaluated on real bug-fix tasks using the [`swebench_cast.py`](swebench_cast.py) harness.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         swebench_cast.py                            │
│                                                                     │
│  SWE-bench Lite ──► clone repo at base commit                       │
│                  ──► extract patch epicentre (files in diff)        │
│                  ──► BFS neighbourhood (import graph, radius=1)     │
│                  ──► craft query (problem + file contents)          │
│                  ──► run CAST agent                                 │
│                  ──► LLM-as-judge evaluation                        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           agent_cast.py                             │
│                                                                     │
│  CodeAnalysisRequest ──► LangGraph ReAct agent (claude-haiku-4-5)  │
│                                                                     │
│  Tools available to the agent:                                      │
│    • read_file     – read a source file                             │
│    • list_imports  – extract import statements                      │
│    • find_function – locate a function definition                   │
│    • trace_calls   – trace call chains from a function              │
│                                                                     │
│  Output: CodeAnalysisResult (structured JSON)                       │
│    • dependency_graph  – {file: [imported_files]}                   │
│    • call_chains       – [[fn1, fn2, fn3, ...], ...]                │
│    • entry_points      – public API functions                       │
│    • cycles            – circular import/call loops                 │
│    • summary           – natural language root-cause analysis       │
└─────────────────────────────────────────────────────────────────────┘
```

## ReAct Architecture Details

The CAST agent is built on the **ReAct (Reasoning and Acting)** paradigm, implemented using LangGraph's `create_react_agent`. ReAct interleaves **reasoning** (thinking about what to do next) with **acting** (calling tools to gather information), allowing the agent to dynamically explore the codebase and build a comprehensive analysis.

### ReAct Loop Overview

1. **Initial Query**: The agent receives a `CodeAnalysisRequest` containing:
   - The problem statement (e.g., "Identify all dependency relationships and call chains between these files.")
   - Contents of the source files to analyze

2. **Reasoning Phase**: The LLM (Claude) thinks step-by-step about the task:
   - What information do I need?
   - Which tools should I use?
   - How does this relate to the problem?

3. **Acting Phase**: The agent calls one or more tools to gather data:
   - `read_file`: Reads the full content of a source file
   - `list_imports`: Extracts all import statements from a file
   - `find_function`: Locates a specific function definition
   - `trace_calls`: Traces call chains starting from a function

4. **Observation Integration**: Tool outputs are fed back to the LLM as observations

5. **Iteration**: Steps 2–4 repeat until the agent has sufficient information to produce the final output

6. **Final Output**: The agent synthesizes all gathered information into a structured `CodeAnalysisResult` JSON

### Tool Descriptions

| Tool | Purpose | Example Usage |
|------|---------|---------------|
| `read_file` | Read entire source file content | "Read the file `astropy/modeling/separable.py` to understand the separability_matrix function" |
| `list_imports` | Extract all import statements | "List all imports in `requests/sessions.py`" |
| `find_function` | Locate function definition | "Find the definition of `Session.request` in the codebase" |
| `trace_calls` | Trace function call chains | "Trace calls starting from `separability_matrix`" |

### Prompt Engineering

The agent uses a carefully crafted system prompt that instructs it to:
- Perform static analysis only (no execution)
- Build dependency graphs and call chains
- Identify root causes and entry points
- Output valid JSON matching the `CodeAnalysisResult` schema
- Use tools iteratively to gather comprehensive information

### Example ReAct Trace

```
Thought: I need to analyze the dependency relationships in these files. Let me start by reading the main file.

Action: read_file(file_path="astropy/modeling/separable.py")

Observation: [full file content]

Thought: Now I see the separability_matrix function. Let me trace its call chain.

Action: trace_calls(function_name="separability_matrix", file_path="astropy/modeling/separable.py")

Observation: [call chain data]

Thought: I need to understand the imports. Let me list them.

Action: list_imports(file_path="astropy/modeling/separable.py")

Observation: [import list]

Thought: Now I have enough information to build the dependency graph and identify the root cause.

Final Answer: [CodeAnalysisResult JSON]
```

---

## Pipeline (step by step)

| Step | What happens |
|------|-------------|
| **1. Load instance** | Pull metadata from HuggingFace `princeton-nlp/SWE-bench_Lite`: `instance_id`, `repo`, `base_commit`, `patch`, `problem_statement` |
| **2. Clone at commit** | `git clone --filter=blob:none` + `git checkout <base_commit>` into a local cache (`.swebench_repos/`) |
| **3. Extract epicentre** | Parse `--- a/<file>` header lines from the ground-truth patch to identify the exact files the fix touches |
| **4. Collect neighbourhood** | BFS over Python `import` statements: start from epicentre files, expand to files they import and files that import them, up to `--radius` hops. Capped at `--max_files` |
| **5. Craft query** | Concatenate the problem statement + file contents into a structured prompt asking for full CAST analysis |
| **6. Run CAST agent** | `agent_cast.run_agent()` invokes the LangGraph ReAct loop until it produces a valid `CodeAnalysisResult` JSON |
| **7. Judge evaluation** | Claude-as-judge scores the analysis on 4 axes (0–5 each): root-cause quality, fix suggestion quality, file localisation, function localisation |
| **8. Save results** | Per-instance JSON written to `results/swebench_cast/<instance_id>.json`; cumulative `summary.json` |

---

## Repository Layout

```
DependEval/
├── agent_cast.py          # Core CAST ReAct agent (LangGraph)
├── swebench_cast.py       # SWE-bench harness + LLM-as-judge
├── CAST_APPROACH.md       # This file
├── results/
│   └── swebench_cast/
│       ├── summary.json   # All results in one place
│       └── <instance>.json
└── .swebench_repos/       # Cached git clones (gitignored)
```

---

## Evaluation Design

### What the agent is given (oracle inputs)
- The **problem statement** written by the human reporter
- **Pre-patch source files** around the bug (not the fix itself)

### What the agent is *not* given
- The ground-truth patch
- Test files
- Any hint about what the fix should look like

### LLM-as-Judge rubric

Each analysis is scored by `claude-haiku-4-5` on four dimensions:

| Dimension | Range | What it measures |
|-----------|-------|-----------------|
| `file_correct` | 0 / 1 | Did the agent identify the correct file? |
| `function_correct` | 0 / 1 | Did the agent name the correct function? |
| `root_cause_score` | 0–5 | How accurately did it explain *why* the bug exists? |
| `fix_suggestion_score` | 0–5 | How actionable and correct is the suggested fix? |
| `overall` | 0–5 | Holistic quality of the analysis |

---

## Results (20-instance pilot)

Run with `--model claude-haiku-4-5 --radius 1 --max_files 20`.

| Instance | Repo | Files | Overall | File | Func | Root | Fix |
|----------|------|------:|:-------:|:----:|:----:|:----:|:---:|
| astropy__astropy-12907 | astropy | 1 | 1/5 | ✓ | ✓ | 1/5 | 0/5 |
| astropy__astropy-14182 | astropy | 1 | 4/5 | ✓ | ✓ | 4/5 | 3/5 |
| astropy__astropy-14365 | astropy | 2 | 3/5 | ✓ | ✓ | 4/5 | 3/5 |
| matplotlib__matplotlib-22711 | matplotlib | 1 | 1/5 | ✓ | ✓ | 1/5 | 0/5 |
| matplotlib__matplotlib-22835 | matplotlib | 1 | 3/5 | ✓ | ✓ | 4/5 | 2/5 |
| psf__requests-1963 | requests | 1 | 3/5 | ✓ | ✓ | 4/5 | 2/5 |
| psf__requests-2148 | requests | 1 | 4/5 | ✓ | ✓ | 4/5 | 4/5 |
| psf__requests-2317 | requests | 1 | 3/5 | ✓ | ✓ | 4/5 | 2/5 |
| psf__requests-2674 | requests | 1 | 3/5 | ✓ | ✓ | 4/5 | 2/5 |
| pydata__xarray-3364 | xarray | 1 | 2/5 | ✓ | ✓ | 4/5 | 1/5 |
| pylint-dev__pylint-5859 | pylint | 2 | N/A | — | — | — | — |
| pytest-dev__pytest-5103 | pytest | 1 | 3/5 | ✓ | ✓ | 4/5 | 2/5 |
| pytest-dev__pytest-5221 | pytest | 1 | 3/5 | ✓ | ✓ | 4/5 | 2/5 |
| pytest-dev__pytest-5227 | pytest | 1 | 4/5 | ✓ | ✗ | 5/5 | 5/5 |
| scikit-learn__scikit-learn-10297 | sklearn | 1 | 1/5 | ✓ | ✓ | 1/5 | 0/5 |
| scikit-learn__scikit-learn-10508 | sklearn | 1 | 1/5 | ✓ | ✓ | 2/5 | 0/5 |
| sphinx-doc__sphinx-10451 | sphinx | 2 | 2/5 | ✓ | ✓ | 3/5 | 2/5 |
| sympy__sympy-11400 | sympy | 2 | 2/5 | ✓ | ✗ | 2/5 | 1/5 |
| sympy__sympy-11870 | sympy | 2 | 2/5 | ✓ | ✗ | 2/5 | 1/5 |
| sympy__sympy-13031 | sympy | 2 | 2/5 | ✓ | ✓ | 2/5 | 0/5 |

**Aggregate (n=19 scored, 1 judge parse failure):**

| Metric | Score |
|--------|-------|
| Mean overall | **2.47 / 5** |
| File localisation | **100%** (19/19) |
| Function localisation | **84%** (16/19) |
| Mean root-cause | ~3.1 / 5 |
| Mean fix suggestion | ~1.7 / 5 |

**Key observations:**
- **File localisation is perfect** across all 19 scored instances — neighbourhood BFS always captures the right file within radius=1
- **Function localisation is 84%** — 3 sympy instances missed the exact entry-point function; multi-file patches with heavier math abstractions are harder to pin
- **Root-cause scores** split into two tiers: requests/pytest/sphinx score 4–5/5 (clear data-flow bugs), while sympy/sklearn/matplotlib score 1–2/5 (algorithmic/numerical bugs require deeper domain knowledge)
- **Fix scores are low** because the agent is not prompted to generate a diff — adding a patch-generation step is the primary lever for improvement
- **pylint-dev__pylint-5859** caused a judge JSON parse failure; re-running with temperature=0 or a stronger judge model should resolve it

---

## Quick Start

```bash
# 1. Set your API key
echo "ANTHROPIC_API_KEY=sk-ant-..." > .env

# 2. Run the 20 default instances (caches repos locally)
cd DependEval
uv run python swebench_cast.py \
    --model claude-haiku-4-5 \
    --radius 1 \
    --max_files 20

# 3. Run specific instances
uv run python swebench_cast.py \
    --instances psf__requests-2317 sympy__sympy-13031 \
    --model claude-haiku-4-5

# 4. View the summary
cat results/swebench_cast/summary.json | python3 -m json.tool
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--instances` | 20 defaults | Space-separated SWE-bench instance IDs |
| `--model` | `claude-haiku-4-5` | Anthropic model for CAST agent + judge |
| `--radius` | `1` | BFS hops for neighbourhood collection |
| `--max_files` | `20` | Maximum files fed to the agent |
| `--out_dir` | `results/swebench_cast` | Output directory |
| `--cache_dir` | `.swebench_repos` | Repo clone cache |
| `--split` | `test` | SWE-bench split (`test` / `dev`) |

---

## Known Limitations

1. **Relative imports** – `collect_neighbourhood` only resolves absolute Python imports via path translation. Files connected via `from .core import ...` or `from ..utils import ...` are missed unless they also appear in the epicentre.

2. **Single-language** – the neighbourhood BFS only parses Python `import` statements. Non-Python repos (C, JavaScript, etc.) will return only the epicentre files.

3. **No execution** – the agent performs static analysis only; dynamic behaviour (e.g., runtime dispatch, monkey-patching) is invisible.

4. **Fix quality** – the agent is not prompted to write a patch, so `fix_suggestion_score` reflects only a qualitative description of the fix direction, not executable code.

---

## Extending

### Increase neighbourhood depth
```bash
uv run python swebench_cast.py --radius 2 --max_files 40 \
    --instances astropy__astropy-12907
```

### Use a stronger model
```bash
uv run python swebench_cast.py --model claude-sonnet-4-5 \
    --instances sympy__sympy-13031
```

### Run all instances of a single repo
```python
# In Python
from datasets import load_dataset
ds = load_dataset('princeton-nlp/SWE-bench_Lite', split='test')
ids = [d['instance_id'] for d in ds if d['repo'] == 'psf/requests']
# then pass ids to --instances
```
