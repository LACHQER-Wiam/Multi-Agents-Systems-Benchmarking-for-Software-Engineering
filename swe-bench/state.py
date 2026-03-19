# state.py
from typing import Annotated, Sequence, TypedDict, List
from langchain_core.messages import BaseMessage
from langgraph.graph.message import add_messages


class SWEState(TypedDict):
    """
    Shared state flowing through the entire A2A pipeline.

    Flow:
        FaultLocalizer
            ↓
        3x CodeAnalyst (parallel) → majority vote
            ↓
        PatchWriter
            ↓
        TestValidator
          ├─ try to run patch (dry-run / syntax check)
          ├─ fallback to LLM if can't run
          └─ PASS → done
             FAIL → back to 3x CodeAnalyst with failure reason
                    (max 3 rounds)
    """

    # ── INPUT ───────────────────────────────────────────────────────
    instance_id:        str
    repo:               str
    problem_statement:  str
    hints_text:         str

    # ── AGENT 1: FAULT LOCALIZER ────────────────────────────────────
    faulty_files:       List[str]
    fault_explanation:  str

    # ── AGENT 2: 3x CODE ANALYST ────────────────────────────────────
    analyst_proposals:  List[dict]   # all 3 proposals
    code_context:       str          # majority vote winner
    root_cause:         str
    fix_direction:      str

    # ── AGENT 3: PATCH WRITER ───────────────────────────────────────
    proposed_patch:     str

    # ── AGENT 4: TEST VALIDATOR ─────────────────────────────────────
    validation_passed:  bool
    validation_method:  str          # "execution", "llm", "execution+llm"
    validation_notes:   str
    failure_reason:     str          # sent back to analysts on FAIL

    # ── DEBATE LOOP ─────────────────────────────────────────────────
    debate_round:       int          # 0, 1, 2, 3
    max_rounds:         int          # always 3
    debate_history:     List[dict]   # [{round, patch, failure_reason, method}]

    # ── HISTORY ─────────────────────────────────────────────────────
    messages: Annotated[Sequence[BaseMessage], add_messages]
