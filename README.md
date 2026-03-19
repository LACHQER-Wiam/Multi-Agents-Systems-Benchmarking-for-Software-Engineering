\documentclass[11pt]{article}
\usepackage[a4paper,vmargin={2.4cm,2.8cm},hmargin={2.4cm,2.4cm}]{geometry}
\usepackage[utf8]{inputenc}
\usepackage{fancyhdr}
\pagestyle{fancy}
\renewcommand{\headrulewidth}{1pt}
\fancyhead[R]{CONFIDENTIAL}
\fancyhead[L]{Team 07 - Project CAST4}
\fancyhead[C]{M2DS Capstone projects, IPP, 2026}
\usepackage{amsmath,amssymb}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{cleveref}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{listings}
\usepackage{xcolor}
\usepackage{enumitem}

\lstset{
  basicstyle=\ttfamily\small,
  breaklines=true,
  frame=single,
  backgroundcolor=\color{gray!8},
  keywordstyle=\color{blue!70!black},
  commentstyle=\color{green!50!black},
  columns=fullflexible,
  keepspaces=true,
  xleftmargin=4pt,
  xrightmargin=4pt,
  aboveskip=8pt,
  belowskip=8pt,
}

\begin{document}

\begin{center}
\textbf{\Large Repository Documentation} \\[0.5em]
\textbf{\large Multi-Agents Systems Benchmarking} \\[0.6em]
Branch: \texttt{Ilyass} \\[0.3em]
\texttt{\small https://github.com/LACHQER-Wiam/Multi-Agents-Systems-Benchmarking-for-Software-Engineering} \\[1.5em]
\end{center}

% ─────────────────────────────────────────────────────────────
\section{What this repository is}

This repository benchmarks multi-agent LLM systems on two distinct software engineering tasks:

\begin{enumerate}[leftmargin=1.8em]
  \item \textbf{DependEval} — dependency ordering: given a set of source files from the same
    project, identify which file depends on which and produce a topologically sorted list (base
    files first, entry points last). Evaluated on a custom dataset spanning eight programming
    languages.

  \item \textbf{SWE-bench} — automated bug fixing: given a real GitHub issue report and a
    repository snapshot, generate a unified diff patch that resolves the described bug. Evaluated
    on SWE-bench Lite (300 tasks).
\end{enumerate}

Both parts use LangGraph for agent orchestration, Claude models (Haiku and Sonnet) as the
underlying LLMs, and LangSmith for tracing. The two tasks are structurally similar — shared
state flowing through specialist agents — but differ in complexity, evaluation methodology, and
the nature of the output.

% ─────────────────────────────────────────────────────────────
\section{Repository structure}

\begin{lstlisting}
.
├── data/DR/                          # DependEval dataset (8 languages)
│   ├── python/task2_python_final.json
│   ├── java/task2_java_final.json
│   ├── javascript/...
│   ├── typescript/...
│   ├── c/...  c++/...  c#/...  php/...
├── DependEval/                       # Dependency ordering agents
│   ├── ReAct.py                      # Single ReAct agent baseline
│   └── completion.py                 # Direct completion baseline
├── results/                          # Benchmark result reports
│   ├── ReAct.md
│   └── completion.md
└── swe-bench/                        # Bug-fixing agents
    ├── state.py
    ├── agents.py
    ├── graph.py
    ├── benchmark.py
    └── schema.md
\end{lstlisting}

% ─────────────────────────────────────────────────────────────
\section{Part 1 — DependEval: dependency ordering}
\label{sec:dependeval}

\subsection{Task definition}

Each task instance is a JSON object containing:
\begin{itemize}[leftmargin=1.8em]
  \item \textbf{\texttt{files}}: a list of filenames belonging to the same project.
  \item \textbf{\texttt{content}}: the merged source code of all files.
  \item \textbf{\texttt{gt}}: the ground-truth topologically sorted list.
\end{itemize}

The ordering rule is: if file B depends on file A (imports it, calls functions defined in it, or
structurally follows from it), then A must appear \emph{before} B in the output list. The
evaluation metric is \textbf{Exact Match Rate (EMR)}: the predicted list must match the ground
truth exactly, element by element, after normalization of path separators and quote characters.

\subsection{Dataset}

The dataset lives under \texttt{data/DR/} and covers eight programming languages:

\begin{center}
\begin{tabular}{ll}
\toprule
\textbf{Language} & \textbf{File} \\
\midrule
Python     & \texttt{data/DR/python/task2\_python\_final.json} \\
Java       & \texttt{data/DR/java/task2\_java\_final.json} \\
JavaScript & \texttt{data/DR/javascript/task2\_javascript\_final.json} \\
TypeScript & \texttt{data/DR/typescript/task2\_typescript\_final.json} \\
C          & \texttt{data/DR/c/task2\_c\_final.json} \\
C++        & \texttt{data/DR/c++/task2\_c++\_final.json} \\
C\#        & \texttt{data/DR/c\#/task2\_c\#\_final.json} \\
PHP        & \texttt{data/DR/php/task2\_php\_final.json} \\
\bottomrule
\end{tabular}
\end{center}

\subsection{Baselines}

Two baselines are implemented for comparison against the A2A system.

\paragraph{\texttt{completion.py} — Direct completion baseline.}
A single LLM call with a prompt asking the model to output the sorted file list. No agent loop,
no tools, no debate. This is the simplest possible approach and establishes the lower bound.
Results are reported in \texttt{results/completion.md}.

\paragraph{\texttt{ReAct.py} — Single ReAct agent baseline.}
A LangGraph ReAct agent equipped with two tools: \texttt{verify\_file\_presence} (confirms a
filename exists in the provided context) and \texttt{get\_file\_snippet} (retrieves a specific
line range from a file). The agent iterates — calling tools to inspect imports and logic — until
it produces the final sorted list. Uses \texttt{claude-haiku-4-5} at temperature 0.2.
Results are reported in \texttt{results/ReAct.md}.

The ReAct agent uses the \texttt{langchain\_community} OpenAI callback to track token usage and
cost per language, and reports input tokens, output tokens, average tokens per example, total
cost, and wall time.
\subsection{Task definition}

SWE-bench Lite contains 300 real GitHub issues drawn from popular Python
repositories (Django, Astropy, and others). Each task instance provides:
\begin{itemize}[leftmargin=1.8em]
  \item \textbf{\texttt{problem\_statement}}: the raw GitHub issue text.
  \item \textbf{\texttt{patch}}: the gold unified diff that resolves the issue (hidden from the
    agent).
  \item \textbf{\texttt{test\_patch}}: the tests that must pass after the fix.
  \item \textbf{\texttt{FAIL\_TO\_PASS}}: test IDs that were failing before the fix and must pass
    after.
\end{itemize}

The agent receives only the issue text and repository metadata. It must produce a unified diff
patch. Official evaluation applies the patch to the repository at the relevant commit and runs the
real test suite; the task is resolved only if all \texttt{FAIL\_TO\_PASS} tests pass and no
previously-passing tests break.

\subsection{File inventory}

\begin{longtable}{p{3.8cm} p{11.6cm}}
\toprule
\textbf{Path} & \textbf{What it does} \\
\midrule
\endhead

\texttt{swe-bench/state.py} &
Defines \texttt{SWEState}, the shared TypedDict flowing through the LangGraph pipeline. Contains
input fields (\texttt{instance\_id}, \texttt{repo}, \texttt{problem\_statement},
\texttt{hints\_text}), agent output fields (\texttt{faulty\_files}, \texttt{analyst\_proposals},
\texttt{root\_cause}, \texttt{fix\_direction}, \texttt{proposed\_patch},
\texttt{validation\_passed}, \texttt{validation\_method}, \texttt{validation\_notes},
\texttt{failure\_reason}), and debate loop fields (\texttt{debate\_round}, \texttt{max\_rounds},
\texttt{debate\_history}). \\[6pt]

\texttt{swe-bench/agents.py} &
Implements all four agent functions and their helpers. Each agent reads \texttt{SWEState} and
returns a partial dict merged back by LangGraph. Contains: \texttt{agent\_fault\_localizer},
\texttt{agent\_code\_analysts} (runs three instances + majority vote),
\texttt{agent\_patch\_writer}, \texttt{agent\_test\_validator} (structural check + LLM review),
and shared helpers \texttt{extract\_section}, \texttt{\_format\_debate\_history},
\texttt{\_try\_run\_patch}, \texttt{\_llm\_validate}, \texttt{\_majority\_vote}. \\[6pt]

\texttt{swe-bench/graph.py} &
Builds and compiles the LangGraph \texttt{StateGraph}. Registers four agent nodes plus an
\texttt{increment\_round} pass-through node. Wires the forward pipeline and the conditional
debate-loop edge: on validator failure with rounds remaining, routes back through
\texttt{increment\_round} $\rightarrow$ \texttt{code\_analysts}. Exposes a \texttt{pipeline}
singleton. \\[6pt]

\texttt{swe-bench/benchmark.py} &
Loads SWE-bench Lite from HuggingFace, iterates over tasks, builds initial state, calls
\texttt{pipeline.invoke()}, and saves all results to \texttt{results.json}. LangSmith tracing
is enabled via environment variables. Configurable \texttt{max\_tasks} parameter (default 50). \\[6pt]

\texttt{swe-bench/schema.md} &
Markdown reference describing the \texttt{SWEState} fields and their types. Useful as a
quick-reference when modifying agents. \\

\bottomrule
\end{longtable}

\subsection{Agent descriptions}

\paragraph{Agent 1 — Fault Localizer.}
\textbf{Model:} \texttt{claude-haiku-4-5}, temperature 0.0.
Reads the issue text and outputs a list of file paths (\texttt{faulty\_files}) and a one-paragraph
explanation (\texttt{fault\_explanation}). Runs once at the start of each task; its output is
never retried in the debate loop.

\paragraph{Agent 2 — Code Analysts (×3, majority vote).}
\textbf{Models:} Three instances of \texttt{claude-haiku-4-5} at temperatures 0.0
(\textit{Conservative}), 0.3 (\textit{Moderate}), and 0.6 (\textit{Creative}). All three run
on the same input and independently produce \texttt{code\_context}, \texttt{root\_cause}, and
\texttt{fix\_direction}. Majority vote selects the winner by 40\% word-overlap similarity between
root-cause strings; ties go to a moderator LLM call. On retry rounds, analysts receive the full
\texttt{failure\_reason} and \texttt{debate\_history} and are explicitly instructed to propose a
different approach.

\paragraph{Agent 3 — Patch Writer.}
\textbf{Model:} \texttt{claude-sonnet-4-5}, temperature 0.2. The only agent using Sonnet, because
generating a correct unified diff is the hardest subtask. Receives all analyst outputs plus the
accumulated debate history on retry rounds. Extracts the diff from a \texttt{```diff ... ```}
code block with a plain-text fallback.

\paragraph{Agent 4 — Test Validator.}
\textbf{Model:} \texttt{claude-haiku-4-5}, temperature 0.0 (LLM step only).
Two-step validation: (1)~structural check — verifies valid unified diff format and runs
\texttt{python -m py\_compile} on dedented added lines; (2)~LLM semantic review if structural
check passes. On failure, produces a structured \texttt{failure\_reason} with a
\texttt{WHAT\_TO\_FIX} field that is passed to the analysts in the next round.

\subsection{Debate loop}

On validator failure with rounds remaining, the graph routes through \texttt{increment\_round}
back to \texttt{code\_analysts}. Maximum three rounds. Every failed patch and its rejection reason
are stored in \texttt{debate\_history} so each subsequent attempt is informed by all previous
failures. If the patch still fails after round 3, the pipeline exits with
\texttt{validation\_passed = False}.

\subsection{Evaluation methodology}

A lightweight evaluator (\texttt{evaluator.py}, run separately) reads \texttt{results.json} and
computes three metrics without Docker or real test execution:

\begin{enumerate}[leftmargin=1.8em]
  \item \textbf{File localization accuracy}: exact and partial match between predicted file paths
    and gold-patch file paths.
  \item \textbf{Patch similarity (composite)}: weighted combination of normalized diff similarity
    (0.4), added-line similarity (0.4), and removed-line similarity (0.2), all computed with
    Python \texttt{SequenceMatcher}.
  \item \textbf{Validator pass rate}: fraction of tasks where the LLM validator returned
    \texttt{VERDICT: PASS}. This is an LLM opinion, not ground-truth test execution.
\end{enumerate}

\subsection{Results on 50 tasks}

\begin{center}
\begin{tabular}{lcc}
\toprule
\textbf{Metric} & \textbf{Value} & \textbf{Notes} \\
\midrule
File localization (exact match) & 90.0\% & Fault Localizer is the strong point \\
Patch similarity (composite)    & 39.5\% & Patch Writer is the bottleneck \\
Validator PASS rate             & 44.0\% & LLM opinion, not pytest \\
Tasks evaluated                 & 50 / 300 & SWE-bench Lite test split \\
\bottomrule
\end{tabular}
\end{center}

\begin{center}
\begin{tabular}{lcccc}
\toprule
\textbf{Repository} & \textbf{Tasks} & \textbf{PASS\%} & \textbf{File acc.} & \textbf{Avg sim.} \\
\midrule
django/django   & 44 & 45\% & 91\% & 40.3\% \\
astropy/astropy &  6 & 33\% & 83\% & 33.2\% \\
\bottomrule
\end{tabular}
\end{center}

Django outperforms Astropy because the model has seen substantially more Django code during
training, Django bugs in this subset tend to require simpler localized fixes, and Astropy issues
involve numerical/astronomical domain knowledge that cannot be verified without code execution.

% ─────────────────────────────────────────────────────────────
\section{swe-bench}

\begin{center}
\begin{tabular}{p{3.8cm} p{5.3cm} p{5.3cm}}
\toprule
\textbf{SWE-bench} \\
\midrule
\textbf{Input}
  & GitHub issue text + repo metadata \\[4pt]
\textbf{Output}
  & Unified diff patch \\[4pt]
\textbf{Evaluation}
  & Patch similarity + validator PASS \\[4pt]
\textbf{Languages}
  & Python only \\[4pt]
\textbf{Agent count}
  & 1 localizer + 3 analysts + 1 patcher + 1 validator \\[4pt]
\textbf{Debate}
  & Up to 3 rounds, analysts retry with failure reason \\[4pt]
\textbf{Difficulty}
  & Full software engineering \\[4pt]
\textbf{Baselines}
  & None (A2A is the only system) \\
\bottomrule
\end{tabular}
\end{center}

% ─────────────────────────────────────────────────────────────
\section{How to reproduce}

\subsection{Prerequisites}

Python 3.11+ (via Conda), an Anthropic API key, and a LangSmith API key (free tier at
\url{https://smith.langchain.com}).

\subsection{Install}

\begin{lstlisting}[language=bash]
git clone https://github.com/LACHQER-Wiam/\
Multi-Agents-Systems-Benchmarking-for-Software-Engineering
cd Multi-Agents-Systems-Benchmarking-for-Software-Engineering
git checkout ilyass
conda create -n swe-bench-a2a python=3.11 -y
conda activate swe-bench-a2a
pip install langchain langchain-anthropic langgraph langsmith \
            python-dotenv datasets
\end{lstlisting}

\subsection{Configure API keys}

Create a \texttt{.env} file at the repo root:

\begin{lstlisting}
ANTHROPIC_API_KEY=your_anthropic_key_here
LANGCHAIN_TRACING_V2=true
LANGCHAIN_API_KEY=your_langsmith_key_here
LANGCHAIN_PROJECT=swe-bench-a2a
\end{lstlisting}

\subsection{Run DependEval baselines}

\begin{lstlisting}[language=bash]
cd DependEval

# Direct completion baseline (one LLM call per example)
python completion.py

# Single ReAct agent baseline
python ReAct.py
\end{lstlisting}

Both scripts loop over all eight languages and print EMR, accuracy, token counts, and cost per
language plus a cross-language summary table.

\subsection{Run DependEval A2A system}

\begin{lstlisting}[language=bash]
cd DependEval
python A2A_benchmark.py
\end{lstlisting}

Runs the three-specialist debate pipeline on all eight languages. Prints per-task
\texttt{MATCH}/\texttt{MISMATCH} status with confidence score, and a final summary showing full
consensus rate, majority vote rate, and moderator usage rate per language.

\subsection{Run SWE-bench A2A system}

\begin{lstlisting}[language=bash]
cd swe-bench

# Test single task (task[0], astropy)
python agents.py
python graph.py

# Full benchmark (50 tasks by default)
python benchmark.py

# Evaluate results
python evaluator.py
\end{lstlisting}

Results are saved to \texttt{swe-bench/results.json}. LangSmith traces are visible at
\url{https://smith.langchain.com} under project \texttt{swe-bench-a2a}.

% ─────────────────────────────────────────────────────────────
\section{Known limitations and next steps}

\paragraph{DependEval — no cross-file execution.}
The agents reason purely from source text. For languages with complex module systems (C++
templates, C\# partial classes), structural heuristics alone are insufficient. A tree-sitter
based parser could extract import graphs deterministically and replace or augment the Import
Analyst.

\paragraph{SWE-bench — Patch Writer has no real file content.}
The Patch Writer never sees the actual lines it is supposed to modify. It reasons from the issue
description and analyst summaries, which causes it to over-engineer patches. The primary planned
improvement is fetching the relevant file content from the GitHub API at the target commit before
calling the Patch Writer.

\paragraph{SWE-bench — no real test execution.}
Validation is limited to diff format checks and LLM reasoning. The true SWE-bench resolved rate
requires the official Docker-based harness
(\texttt{swebench.harness.run\_evaluation}).

\paragraph{Sequential analysts.}
The three Code Analysts (both in DependEval and SWE-bench) run sequentially. Parallelising them
via LangGraph's fan-out API would reduce latency by approximately $2\times$.

\paragraph{Majority vote heuristic.}
The 40\% word-overlap threshold for declaring analyst agreement is a heuristic. Embedding-based
similarity or a dedicated comparison LLM call would be more robust.

\end{document}
