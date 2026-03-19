# graph.py
from langgraph.graph import StateGraph, END
from state import SWEState
from agents import (
    agent_fault_localizer,
    agent_code_analysts,
    agent_patch_writer,
    agent_test_validator,
)


# ════════════════════════════════════════════════════════════
# ROUTING LOGIC
# ════════════════════════════════════════════════════════════

def route_after_validator(state: SWEState) -> str:
    """
    After TestValidator:
      - PASS           → END
      - FAIL + rounds left → back to code_analysts (debate)
      - FAIL + no rounds   → END (give up)
    """
    if state["validation_passed"]:
        print(f"\n[Router] ✅ PASS → ending pipeline")
        return END

    round_num  = state.get("debate_round", 0)
    max_rounds = state.get("max_rounds",   3)

    if round_num < max_rounds:
        print(f"\n[Router] ❌ FAIL — Round {round_num}/{max_rounds} → sending back to analysts")
        return "retry"
    else:
        print(f"\n[Router] ❌ FAIL — Max rounds ({max_rounds}) reached → giving up")
        return END


def increment_round(state: SWEState) -> dict:
    """Increment debate round before sending back to analysts."""
    return {"debate_round": state.get("debate_round", 0) + 1}


# ════════════════════════════════════════════════════════════
# BUILD THE GRAPH
# ════════════════════════════════════════════════════════════

def build_graph():
    g = StateGraph(SWEState)

    # ── Nodes ────────────────────────────────────────────────
    g.add_node("fault_localizer",  agent_fault_localizer)
    g.add_node("code_analysts",    agent_code_analysts)      # 3x analysts + vote
    g.add_node("patch_writer",     agent_patch_writer)
    g.add_node("test_validator",   agent_test_validator)
    g.add_node("increment_round",  increment_round)          # bumps debate_round

    # ── Entry ────────────────────────────────────────────────
    g.set_entry_point("fault_localizer")

    # ── Forward pipeline ─────────────────────────────────────
    g.add_edge("fault_localizer", "code_analysts")
    g.add_edge("code_analysts",   "patch_writer")
    g.add_edge("patch_writer",    "test_validator")

    # ── Debate loop ──────────────────────────────────────────
    #
    #   test_validator
    #     ├─ PASS  → END
    #     └─ FAIL  → increment_round → code_analysts → patch_writer → test_validator
    #
    g.add_conditional_edges(
        "test_validator",
        route_after_validator,
        {
            "retry": "increment_round",
            END:     END,
        }
    )
    g.add_edge("increment_round", "code_analysts")

    return g.compile()


pipeline = build_graph()


# ════════════════════════════════════════════════════════════
# QUICK TEST
# ════════════════════════════════════════════════════════════
if __name__ == "__main__":
    from datasets import load_dataset

    dataset = load_dataset("princeton-nlp/SWE-bench_Lite", split="test")
    task    = dataset[0]

    initial_state: SWEState = {
        "instance_id":       task["instance_id"],
        "repo":              task["repo"],
        "problem_statement": task["problem_statement"],
        "hints_text":        task.get("hints_text", ""),
        "faulty_files":      [],
        "fault_explanation": "",
        "analyst_proposals": [],
        "code_context":      "",
        "root_cause":        "",
        "fix_direction":     "",
        "proposed_patch":    "",
        "validation_passed": False,
        "validation_method": "",
        "validation_notes":  "",
        "failure_reason":    "",
        "debate_round":      0,
        "max_rounds":        3,
        "debate_history":    [],
        "messages":          [],
    }

    print("\n🚀 Running debate pipeline...\n")
    final = pipeline.invoke(initial_state)

    print(f"\n{'='*60}")
    print("✅ GRAPH COMPLETE")
    print(f"{'='*60}")
    print(f"Instance     : {final['instance_id']}")
    print(f"Faulty files : {final['faulty_files']}")
    print(f"Debate rounds: {final['debate_round']}")
    print(f"Validated    : {'✅ PASS' if final['validation_passed'] else '❌ FAIL'}")
    print(f"Method       : {final['validation_method']}")

    if final["debate_history"]:
        print(f"\nDebate history ({len(final['debate_history'])} failed rounds):")
        for h in final["debate_history"]:
            print(f"  Round {h['round']}: {h['failure_reason'][:100]}...")
