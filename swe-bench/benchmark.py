# benchmark.py
import os
import json
import time
from dotenv import load_dotenv
from datasets import load_dataset
from graph import pipeline
from state import SWEState

load_dotenv()

# ════════════════════════════════════════════════════════════
# BENCHMARK RUNNER
# ════════════════════════════════════════════════════════════

def run_benchmark(max_tasks: int = 5, save_results: bool = True):
    """
    Run the A2A pipeline on SWE-bench Lite tasks.

    Args:
        max_tasks:    How many tasks to run (default 5 for testing, set 300 for full run)
        save_results: Save outputs to results.json
    """

    print("\n" + "═"*60)
    print("  SWE-BENCH LITE — A2A MULTI-AGENT BENCHMARK")
    print("  Agents: FaultLocalizer → CodeAnalyst → PatchWriter → TestValidator")
    print("═"*60)

    # ── Load dataset ──────────────────────────────────────────
    dataset = load_dataset("princeton-nlp/SWE-bench_Lite", split="test")
    tasks   = list(dataset)[:max_tasks]
    total   = len(tasks)

    print(f"\n  Tasks to run : {total}")
    print(f"  LangSmith    : {'✅ ON' if os.getenv('LANGCHAIN_TRACING_V2') == 'true' else '⚠️  OFF'}")
    print(f"  Project      : {os.getenv('LANGCHAIN_PROJECT', 'swe-bench-a2a')}\n")

    # ── Tracking ──────────────────────────────────────────────
    results      = []
    errors       = 0
    validated    = 0
    start_time   = time.time()

    for i, task in enumerate(tasks):
        print(f"[{i+1:>3}/{total}] {task['instance_id']}", end=" ... ", flush=True)
        task_start = time.time()

        # ── Build initial state ────────────────────────────────
        initial_state: SWEState = {
            "instance_id":       task["instance_id"],
            "repo":              task["repo"],
            "problem_statement": task["problem_statement"],
            "hints_text":        task.get("hints_text", ""),
            "faulty_files":      [],
            "fault_explanation": "",
            "code_context":      "",
            "root_cause":        "",
            "proposed_patch":    "",
            "validation_passed": False,
            "validation_notes":  "",
            "messages":          [],
        }

        try:
            # ── Run the full graph ─────────────────────────────
            final_state = pipeline.invoke(
                initial_state,
                config={
                    # LangSmith will group all runs under this project
                    "run_name": task["instance_id"],
                    "tags":     [task["repo"], "swe-bench-lite"],
                }
            )

            task_time  = time.time() - task_start
            did_pass   = final_state["validation_passed"]
            if did_pass:
                validated += 1

            status = "✅ PASS" if did_pass else "❌ FAIL"
            print(f"{status}  ({task_time:.1f}s)")

            # ── Store result ───────────────────────────────────
            results.append({
                "instance_id":       task["instance_id"],
                "repo":              task["repo"],
                "faulty_files":      final_state["faulty_files"],
                "fault_explanation": final_state["fault_explanation"],
                "root_cause":        final_state["root_cause"],
                "proposed_patch":    final_state["proposed_patch"],
                "validation_passed": did_pass,
                "validation_notes":  final_state["validation_notes"],
                "time_seconds":      round(task_time, 2),
                # Gold patch for manual comparison
                "gold_patch":        task["patch"],
            })

        except Exception as e:
            errors += 1
            task_time = time.time() - task_start
            print(f"⚠️  ERROR: {e}  ({task_time:.1f}s)")
            results.append({
                "instance_id": task["instance_id"],
                "repo":        task["repo"],
                "error":       str(e),
                "time_seconds": round(task_time, 2),
            })

    # ── Save results ───────────────────────────────────────────
    if save_results:
        output_path = "results.json"
        with open(output_path, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\n  💾 Results saved to {output_path}")

    # ── Final summary ──────────────────────────────────────────
    total_time = time.time() - start_time
    completed  = total - errors

    print("\n" + "═"*60)
    print("  BENCHMARK COMPLETE")
    print("═"*60)
    print(f"  Total tasks      : {total}")
    print(f"  Completed        : {completed}")
    print(f"  Errors           : {errors}")
    print(f"  Validator PASS   : {validated} / {completed}  ({(validated/completed*100):.1f}% if completed > 0 else 0%)")
    print(f"  Total time       : {total_time:.1f}s")
    print(f"  Avg time/task    : {total_time/total:.1f}s")
    print("═"*60)

    if os.getenv("LANGCHAIN_TRACING_V2") == "true":
        print(f"\n  📊 View full traces at: https://smith.langchain.com")
        print(f"     Project: {os.getenv('LANGCHAIN_PROJECT', 'swe-bench-a2a')}")

    return results


# ════════════════════════════════════════════════════════════
# ENTRY POINT
# ════════════════════════════════════════════════════════════

if __name__ == "__main__":
    run_benchmark(
        max_tasks=50,      # ← change to 300 for the full benchmark
        save_results=True
    )