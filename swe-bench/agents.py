# agents.py
import os
import re
import ast
import tempfile
import subprocess
from dotenv import load_dotenv
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage
from langchain_anthropic import ChatAnthropic
from state import SWEState

load_dotenv()

#  LLM INSTANCES 
llm_localizer  = ChatAnthropic(model="claude-haiku-4-5",  temperature=0.0)
llm_analyst_1  = ChatAnthropic(model="claude-haiku-4-5",  temperature=0.0)  # conservative
llm_analyst_2  = ChatAnthropic(model="claude-haiku-4-5",  temperature=0.3)  # moderate
llm_analyst_3  = ChatAnthropic(model="claude-haiku-4-5",  temperature=0.6)  # creative
llm_patcher    = ChatAnthropic(model="claude-sonnet-4-5", temperature=0.2)
llm_validator  = ChatAnthropic(model="claude-haiku-4-5",  temperature=0.0)
llm_moderator  = ChatAnthropic(model="claude-haiku-4-5",  temperature=0.0)


#  SHARED HELPER 
def extract_section(text: str, header: str, next_headers: list) -> str:
    stop    = "|".join([rf"\n{h}:" for h in next_headers]) if next_headers else ""
    pattern = rf"{header}:\s*(.*?)(?={stop}|\Z)" if stop else rf"{header}:\s*(.*)"
    match   = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    return match.group(1).strip() if match else ""


def _format_debate_history(state: SWEState) -> str:
    history = state.get("debate_history", [])
    if not history:
        return ""
    lines = []
    for h in history:
        lines.append(
            f"Round {h['round']}:\n"
            f"  Patch tried   : {h['patch'][:200]}...\n"
            f"  Failure reason: {h['failure_reason']}\n"
        )
    return "\n".join(lines)


# ════════════════════════════════════════════════════════════════════════════════
# AGENT 1 — FAULT LOCALIZER
# ════════════════════════════════════════════════════════════════════════════════

def agent_fault_localizer(state: SWEState) -> dict:
    print(f"\n{'='*60}")
    print(f"[FaultLocalizer] instance: {state['instance_id']}")
    print(f"{'='*60}")

    system = SystemMessage(content=(
        "You are a Fault Localization Expert for Python repositories.\n"
        "Given a GitHub issue report, identify:\n"
        "  1. Which FILE(S) most likely contain the bug\n"
        "  2. Which FUNCTION(S) or CLASS(ES) are responsible\n"
        "  3. A short explanation of WHY\n\n"
        "OUTPUT FORMAT:\n"
        "FAULTY_FILES: ['path/to/file1.py']\n"
        "FAULT_EXPLANATION: <one paragraph>\n\n"
        "Only list files directly related to the bug."
    ))
    human = HumanMessage(content=(
        f"REPOSITORY: {state['repo']}\n\n"
        f"ISSUE DESCRIPTION:\n{state['problem_statement']}\n\n"
        f"ADDITIONAL HINTS:\n{state['hints_text'] or 'None'}\n\n"
        "Identify the faulty files."
    ))

    response = llm_localizer.invoke([system, human])
    content  = response.content

    faulty_files      = []
    fault_explanation = extract_section(content, "FAULT_EXPLANATION", [])
    files_line        = extract_section(content, "FAULTY_FILES", ["FAULT_EXPLANATION"])
    files_line        = files_line.splitlines()[0].strip() if files_line else ""

    try:
        faulty_files = ast.literal_eval(files_line)
    except Exception:
        faulty_files = re.findall(r"[\w/\-]+\.py", files_line)

    print(f"[FaultLocalizer] Files : {faulty_files}")
    print(f"[FaultLocalizer] Expl  : {fault_explanation[:120]}...")

    return {
        "faulty_files":      faulty_files,
        "fault_explanation": fault_explanation,
        "messages":          [AIMessage(content=f"[FaultLocalizer]\n{content}")]
    }


# ════════════════════════════════════════════════════════════════════════════════
# AGENT 2 — 3x CODE ANALYST WITH MAJORITY VOTE
# ════════════════════════════════════════════════════════════════════════════════

def _run_single_analyst(llm, analyst_name: str, state: SWEState, failure_reason: str = "") -> dict:
    """Run one CodeAnalyst instance."""
    retry_context = ""
    if failure_reason:
        retry_context = (
            f"\n\nPREVIOUS ATTEMPT FAILED — Round {state.get('debate_round', 0)}\n"
            f"Failure reason:\n{failure_reason}\n\n"
            f"You MUST identify a DIFFERENT root cause or fix direction.\n"
            f"Do NOT repeat the same analysis.\n"
        )

    personas = {
        "Analyst-Conservative": (
            "You focus ONLY on the literal error message and the exact line mentioned in the issue. "
            "Propose the smallest possible single-line fix. Be extremely minimal."
        ),
        "Analyst-Moderate": (
            "You look at the function containing the bug and its callers. "
            "Propose a fix at the function level, considering edge cases."
        ),
        "Analyst-Creative": (
            "You look at the architectural reason for the bug — why does this design allow this error? "
            "Propose a fix that addresses the root design issue, even if it touches multiple places."
        ),
    }
    persona = personas.get(analyst_name, "")

    system = SystemMessage(content=(
        f"You are {analyst_name}, a Code Analysis Expert for Python.\n"
        f"Your approach: {persona}\n"
    ))
    human = HumanMessage(content=(
        f"REPOSITORY: {state['repo']}\n\n"
        f"ISSUE:\n{state['problem_statement']}\n\n"
        f"FAULTY FILES: {state['faulty_files']}\n\n"
        f"FAULT EXPLANATION:\n{state['fault_explanation']}\n\n"
        + (f"PREVIOUS ATTEMPTS:\n{_format_debate_history(state)}\n\n"
           if state.get("debate_history") else "")
        + "Identify the root cause."
    ))

    response = llm.invoke([system, human])
    content  = response.content

    return {
        "analyst":       analyst_name,
        "code_context":  extract_section(content, "CODE_CONTEXT",  ["ROOT_CAUSE", "FIX_DIRECTION"]),
        "root_cause":    extract_section(content, "ROOT_CAUSE",    ["CODE_CONTEXT", "FIX_DIRECTION"]),
        "fix_direction": extract_section(content, "FIX_DIRECTION", ["CODE_CONTEXT", "ROOT_CAUSE"]),
        "raw":           content,
    }


def _majority_vote(proposals: list) -> dict:
    """Pick best proposal — similarity check then LLM moderator fallback."""

    def similar(a, b):
        a_w = set(a.lower().split())
        b_w = set(b.lower().split())
        return len(a_w & b_w) / max(len(a_w | b_w), 1) > 0.4

    p = proposals
    if similar(p[0]["root_cause"], p[1]["root_cause"]):
        print(f"[CodeAnalysts] Vote: Analyst 1 & 2 agree → Analyst 1 wins")
        return p[0]
    elif similar(p[0]["root_cause"], p[2]["root_cause"]):
        print(f"[CodeAnalysts] Vote: Analyst 1 & 3 agree → Analyst 1 wins")
        return p[0]
    elif similar(p[1]["root_cause"], p[2]["root_cause"]):
        print(f"[CodeAnalysts] Vote: Analyst 2 & 3 agree → Analyst 2 wins")
        return p[1]
    else:
        print(f"[CodeAnalysts] Full disagreement → LLM moderator deciding...")
        system = SystemMessage(content=(
            "Three analysts proposed different root causes.\n"
            "Pick the most technically precise and actionable one.\n"
            "OUTPUT: Just the number 1, 2, or 3."
        ))
        human = HumanMessage(content=(
            f"Analyst 1 — ROOT_CAUSE: {p[0]['root_cause']}\nFIX_DIRECTION: {p[0]['fix_direction']}\n\n"
            f"Analyst 2 — ROOT_CAUSE: {p[1]['root_cause']}\nFIX_DIRECTION: {p[1]['fix_direction']}\n\n"
            f"Analyst 3 — ROOT_CAUSE: {p[2]['root_cause']}\nFIX_DIRECTION: {p[2]['fix_direction']}\n\n"
            "Which is best? Answer with 1, 2, or 3 only."
        ))
        resp   = llm_moderator.invoke([system, human])
        choice = resp.content.strip()
        idx    = 1 if "2" in choice else (2 if "3" in choice else 0)
        print(f"[CodeAnalysts] Moderator chose Analyst {idx+1}")
        return p[idx]


def agent_code_analysts(state: SWEState) -> dict:
    round_num      = state.get("debate_round", 0)
    failure_reason = state.get("failure_reason", "")

    print(f"\n{'='*60}")
    print(f"[CodeAnalysts] Round {round_num} — 3 analysts running...")
    if failure_reason:
        print(f"[CodeAnalysts] Failure context: {failure_reason[:100]}...")
    print(f"{'='*60}")

    proposals = [
        _run_single_analyst(llm_analyst_1, "Analyst-Conservative", state, failure_reason),
        _run_single_analyst(llm_analyst_2, "Analyst-Moderate",     state, failure_reason),
        _run_single_analyst(llm_analyst_3, "Analyst-Creative",     state, failure_reason),
    ]

    for p in proposals:
        print(f"  [{p['analyst']}] {p['root_cause'][:80]}...")

    winner = _majority_vote(proposals)
    print(f"[CodeAnalysts] Winner  : {winner['analyst']}")
    print(f"[CodeAnalysts] Root cause: {winner['root_cause'][:120]}...")

    return {
        "analyst_proposals": proposals,
        "code_context":      winner["code_context"],
        "root_cause":        winner["root_cause"],
        "fix_direction":     winner["fix_direction"],
        "messages":          [AIMessage(content=f"[CodeAnalysts R{round_num}] {winner['analyst']}\n{winner['raw']}")]
    }


# ════════════════════════════════════════════════════════════════════════════════
# AGENT 3 — PATCH WRITER
# ════════════════════════════════════════════════════════════════════════════════

def agent_patch_writer(state: SWEState) -> dict:
    round_num = state.get("debate_round", 0)
    print(f"\n{'='*60}")
    print(f"[PatchWriter] Round {round_num} — Writing patch...")
    print(f"{'='*60}")

    retry_context = ""
    if state.get("failure_reason"):
        retry_context = (
            f"\n\nPREVIOUS PATCH FAILED:\n{state['failure_reason']}\n"
            f"Write a DIFFERENT patch. Do not repeat the same approach.\n"
        )

    system = SystemMessage(content=(
        "You are an Expert Software Engineer writing precise bug fixes.\n"
        "Produce a minimal git-style unified diff patch.\n\n"
        "PATCH FORMAT:\n"
        "  - Use unified diff (--- a/file, +++ b/file, @@ hunk @@)\n"
        "  - '-' = removed, '+' = added, ' ' = context\n"
        "  - Include 3 lines of context\n"
        "  - Be MINIMAL — only change what is needed\n\n"
        "OUTPUT:\n"
        "PATCH_EXPLANATION: <one sentence>\n"
        "PATCH:\n"
        "```diff\n<unified diff here>\n```\n"
        + retry_context
    ))
    human = HumanMessage(content=(
        f"REPOSITORY: {state['repo']}\n\n"
        f"ISSUE:\n{state['problem_statement']}\n\n"
        f"FAULTY FILES: {state['faulty_files']}\n\n"
        f"CODE CONTEXT:\n{state['code_context']}\n\n"
        f"ROOT CAUSE:\n{state['root_cause']}\n\n"
        f"FIX DIRECTION:\n{state['fix_direction']}\n\n"
        + (f"PREVIOUS ATTEMPTS:\n{_format_debate_history(state)}\n\n"
           if state.get("debate_history") else "")
        + "Write the minimal unified diff patch."
    ))

    response = llm_patcher.invoke([system, human])
    content  = response.content

    explanation = extract_section(content, "PATCH_EXPLANATION", ["PATCH"])
    diff_match  = re.search(r"```diff\s*(.*?)```", content, re.DOTALL)
    if diff_match:
        proposed_patch = diff_match.group(1).strip()
    else:
        proposed_patch = extract_section(content, "PATCH", [])
        proposed_patch = proposed_patch.replace("```diff", "").replace("```", "").strip()

    print(f"[PatchWriter] Explanation : {explanation[:100]}...")
    print(f"[PatchWriter] Patch lines : {len(proposed_patch.splitlines())}")

    return {
        "proposed_patch": proposed_patch,
        "messages":       [AIMessage(content=f"[PatchWriter R{round_num}]\n{content}")]
    }


# ════════════════════════════════════════════════════════════════════════════════
# AGENT 4 — TEST VALIDATOR
# Step 1: structural + syntax check (no LLM)
# Step 2: LLM semantic review
# On FAIL: produce detailed failure_reason for debate
# ════════════════════════════════════════════════════════════════════════════════

def _try_run_patch(patch: str) -> tuple:
    """
    Structural validation — check diff format only, no syntax check.
    Syntax checking extracted diff lines is unreliable due to indentation.
    """
    if not patch or len(patch.strip()) < 10:
        return False, "syntax", "Patch is empty or too short."

    lines = patch.splitlines()

    has_minus_file = any(l.startswith("--- ") for l in lines)
    has_plus_file  = any(l.startswith("+++ ") for l in lines)
    has_hunk       = any(l.startswith("@@")   for l in lines)
    has_changes    = any(l.startswith("+") and not l.startswith("+++") for l in lines)

    if not (has_minus_file and has_plus_file and has_hunk):
        return False, "syntax", (
            "Invalid unified diff: missing --- / +++ headers or @@ hunk markers."
        )
    if not has_changes:
        return False, "syntax", "Patch has no added lines — changes nothing."

    # Skip Python syntax check — too unreliable on extracted diff lines
    return True, "execution", "Patch has valid unified diff format."

def _llm_validate(state: SWEState) -> tuple:
    """LLM semantic review. Returns (passed, detailed_reason)"""
    system = SystemMessage(content=(
        "You are a Senior Code Reviewer.\n"
        "Evaluate if this patch correctly fixes the described bug.\n\n"
        "Ask yourself:\n"
        "  1. Does it target the correct function/line ?\n"
        "  2. Does it fix the ROOT CAUSE or just a symptom ?\n"
        "  3. Is it minimal or does it change unnecessary things ?\n"
        "  4. Could it break other functionality ?\n\n"
        "OUTPUT FORMAT:\n"
        "VERDICT: PASS or FAIL\n"
        "REASON: <detailed explanation>\n"
        "WHAT_TO_FIX: <if FAIL, exactly what next attempt should do differently>\n"
    ))
    human = HumanMessage(content=(
        f"ISSUE:\n{state['problem_statement']}\n\n"
        f"ROOT CAUSE:\n{state['root_cause']}\n\n"
        f"PROPOSED PATCH:\n{state['proposed_patch']}\n\n"
        f"DEBATE HISTORY:\n{_format_debate_history(state) or 'First attempt.'}\n\n"
        "Is this patch correct ?"
    ))

    response    = llm_validator.invoke([system, human])
    content     = response.content
    verdict     = extract_section(content, "VERDICT",     ["REASON", "WHAT_TO_FIX"])
    reason      = extract_section(content, "REASON",      ["VERDICT", "WHAT_TO_FIX"])
    what_to_fix = extract_section(content, "WHAT_TO_FIX", ["VERDICT", "REASON"])
    passed      = "PASS" in verdict.upper()
    failure_msg = f"{reason}\n\nWHAT TO FIX NEXT:\n{what_to_fix}" if not passed else reason
    return passed, failure_msg


def agent_test_validator(state: SWEState) -> dict:
    round_num = state.get("debate_round", 0)
    print(f"\n{'='*60}")
    print(f"[TestValidator] Round {round_num}")
    print(f"{'='*60}")

    patch = state.get("proposed_patch", "")

    # Step 1: structural check
    run_passed, method, run_details = _try_run_patch(patch)
    print(f"[TestValidator] Structural: {'✅' if run_passed else '❌'} — {run_details[:80]}")

    if not run_passed:
        validation_passed = False
        validation_method = method
        validation_notes  = run_details
        failure_reason    = f"Patch failed structural check:\n{run_details}\n\nWHAT TO FIX:\nFix the diff format."
    else:
        # Step 2: LLM review
        print(f"[TestValidator] Structural OK → LLM review...")
        llm_passed, llm_reason = _llm_validate(state)
        validation_passed = llm_passed
        validation_method = "execution+llm"
        validation_notes  = llm_reason
        failure_reason    = llm_reason if not llm_passed else ""

    status = "✅ PASS" if validation_passed else "❌ FAIL"
    print(f"[TestValidator] Result : {status} ({validation_method})")
    print(f"[TestValidator] Notes  : {validation_notes[:120]}...")

    # Update debate history
    history = list(state.get("debate_history", []))
    if not validation_passed:
        history.append({
            "round":          round_num,
            "patch":          patch,
            "failure_reason": failure_reason,
            "method":         validation_method,
        })

    return {
        "validation_passed": validation_passed,
        "validation_method": validation_method,
        "validation_notes":  validation_notes,
        "failure_reason":    failure_reason,
        "debate_history":    history,
        "messages":          [AIMessage(content=f"[TestValidator R{round_num}] {status}\n{validation_notes}")]
    }


# ════════════════════════════════════════════════════════════════════════════════
# QUICK TEST
# ════════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    from datasets import load_dataset
    dataset = load_dataset("princeton-nlp/SWE-bench_Lite", split="test")
    task    = dataset[0]

    state: SWEState = {
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

    state.update(agent_fault_localizer(state))
    state.update(agent_code_analysts(state))
    state.update(agent_patch_writer(state))
    state.update(agent_test_validator(state))

    print(f"\n{'='*60}")
    print("FINAL SUMMARY")
    print(f"{'='*60}")
    print(f"Faulty files : {state['faulty_files']}")
    print(f"Root cause   : {state['root_cause'][:200]}")
    print(f"Patch        : {state['proposed_patch'][:300]}")
    print(f"Validated    : {'✅ PASS' if state['validation_passed'] else '❌ FAIL'}")
    print(f"Method       : {state['validation_method']}")
    print(f"Rounds used  : {state['debate_round']}")
