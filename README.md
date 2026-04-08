# Multi-Agent Systems Benchmarking for Software Engineering
**Team 07 - Project CAST4 | M2DS Capstone Projects, IPP, 2026**

[![Branch: Ilyass](https://img.shields.io/badge/Branch-Ilyass-blue)](https://github.com/LACHQER-Wiam/Multi-Agents-Systems-Benchmarking-for-Software-Engineering/tree/Ilyass)

## 📖 Project Overview
This repository benchmarks multi-agent LLM systems on two critical software engineering tasks using **LangGraph** for orchestration and **Claude 3.5 (Haiku/Sonnet)** as the core reasoning engines.

1.  **DependEval (Dependency Ordering):** Identifying file-to-file dependencies and producing a topologically sorted list (base files first, entry points last).
2.  **SWE-bench (Automated Bug Fixing):** Generating functional unified diff patches from real GitHub issue reports across 300 tasks (SWE-bench Lite).

---

## 🏗️ Project Summary: What We Built

We designed a high-reliability pipeline that moves beyond simple LLM prompting into a sophisticated **Multi-Agent Consensus & Debate** architecture.

### Key Innovation: The SWE-bench A2A Pipeline
The core of our bug-fixing system follows a structured, iterative flow:

1.  **FaultLocalizer:** Analyzes the issue text to pinpoint exactly which files in the repository are likely responsible for the bug.
2.  **3x CodeAnalyst (Parallel & Diverse):** We run three independent analyst instances at different temperatures (Conservative, Moderate, Creative) simultaneously.
    * **Majority Vote:** A logic layer compares the three proposed root causes. If they align (using word-overlap and similarity heuristics), we proceed with a high-confidence plan.
3.  **PatchWriter:** A high-capability model (Claude 3.5 Sonnet) takes the agreed-upon root cause and generates a precise unified diff patch.
4.  **TestValidator (The Gatekeeper):**
    * **Step 1 (Execution):** Attempts to actually apply the patch and run basic compilation/syntax checks.
    * **Step 2 (Semantic Review):** If execution isn't possible, an LLM "Reasons" about the patch's validity.
    * **Feedback Loop:** If the patch fails, the **Failure Reason** is fed back to the 3x CodeAnalysts. They start a new round (max 3 rounds) to propose a different approach based on why the previous one failed.

---

## 📂 Repository Structure

```text
.
├── data/DR/                # DependEval dataset (8 languages: Python, Java, JS, TS, etc.)
├── DependEval/             # Dependency ordering agent implementations
│   ├── ReAct.py            # Single ReAct agent baseline
│   ├── A2A_benchmark.py    # Multi-agent debate pipeline
│   └── completion.py       # Direct completion baseline
├── results/                # Benchmark result reports and logs
└── swe-bench/              # Bug-fixing agents (A2A System)
    ├── state.py            # SWEState definition (TypedDict)
    ├── agents.py           # FaultLocalizer, Analysts, Patcher, Validator
    ├── graph.py            # LangGraph workflow definition
    ├── benchmark.py        # Main execution loop for SWE-bench Lite
    └── schema.md           # State field reference
