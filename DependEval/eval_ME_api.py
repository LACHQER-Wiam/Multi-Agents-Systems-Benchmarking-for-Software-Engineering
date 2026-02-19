"""
eval_ME_api.py - Simple evaluation using Claude API.
Tracks token usage and saves cost metrics to Excel.
"""

import json
import argparse
import os
import pandas as pd
from typing import Any, Dict
from openai import OpenAI
# import anthropic
import time
from dotenv import load_dotenv
load_dotenv()


llm_judge_prompt = '''
Gt: {gt}
Pred: {pred}

Using Gt as the correct answer, compare the content of Pred with Gt and evaluate Pred based on the following aspects. Each aspect contains tailored evaluation criteria to handle the complexities of multi-file interactions and feature integration. The output must follow the JSON format described in Point 6.

Evaluation Aspects

1. Correctness of Function Calls 
Objective: Evaluate the accuracy of all function calls between segments and across files.
	•	Ensure:
	•	Each invoking_code_segment correctly calls its corresponding called_code_segment as per Gt.
	•	Calls include appropriate parameter matching, order, and context alignment.
	•	Evaluation Criteria:
	•	Does the function signature match, including parameter names, types, and order?
	•	Are correct arguments passed, meeting expectations in feature_description and detailed_feature_description?
	•	Is the pre- or post-logic necessary for context included?
	•	Are cross-file dependencies invoked correctly, as shown in modified_complete_code?

Scoring Rules:
	•	5 points: All function calls are completely correct and match Gt, including parameters, order, and logical dependencies.
	•	4 points: Mostly correct with minor parameter or comment issues but no major gaps.
	•	3 points: Partially correct; missing key parameters, logic, or dependencies.
	•	2 points: Significant issues in invocation logic, causing likely runtime errors.
	•	0-1 points: Calls are incorrect, incomplete, or not implemented.

2. Alignment with Feature Requirements
Objective: Check if the code in Pred aligns with the intended feature and modification goals.
	•	Ensure:
	•	Every call reflects requirements in feature_description and detailed_feature_description.
	•	The new or modified logic directly implements the required functionality.
	•	Evaluation Criteria:
	•	Does the logic adhere to the functional goals described?
	•	Does it integrate with multi-file dependencies correctly (if applicable)?
	•	Are the new components in new_file_code_segment aligned with expectations?

Scoring Rules:
	•	5 points: Perfectly aligned with feature requirements; implementation is logically complete.
	•	4 points: Correctly aligned but with potential optimizations or minor improvements.
	•	3 points: Partially fulfills requirements with clear gaps in alignment.
	•	2 points: Loosely aligned with significant logic missing.
	•	0-1 points: Not aligned or entirely unrelated to the described requirements.

3. Accuracy of Functionality Implementation
Objective: Verify the correctness of the implementation, focusing on functional outcomes.
	•	Evaluation Criteria:
	•	Does the functionality fully satisfy the requirements in feature_description?
	•	Are components correctly loaded, initialized, or referenced?
	•	Are all dependencies resolved for seamless multi-file integration?

Scoring Rules:
	•	5 points: Fully accurate implementation without functional defects.
	•	4 points: Mostly accurate with minor issues or deviations.
	•	3 points: Partially correct but lacking essential steps or logic.
	•	2 points: Basic framework present but largely incomplete.
	•	0-1 points: Non-functional due to missing or incorrect logic.

4. Completeness of Implementation
Objective: Ensure that all functional components, including new and modified ones, are fully implemented.
	•	Evaluation Criteria:
	•	Are all required segments across files defined and updated per Gt?
	•	Does the implementation cover all subparts described in detailed_feature_description?
	•	Are all new dependencies (#New segments) and modifications (#Modify segments) accounted for?

Scoring Rules:
	•	5 points: Complete implementation with no omissions.
	•	4 points: Nearly complete, with only minor omissions.
	•	3 points: Significant missing functionality, but partially meets requirements.
	•	2 points: Too many missing components, achieving minimal functionality.
	•	0-1 points: Nearly all components are missing or incorrect.

5. Code Quality
Objective: Assess the overall quality, maintainability, and readability of the code.
	•	Evaluation Criteria:
	•	Readability: Clear naming, concise comments, and consistent style.
	•	Maintainability: Modular structure, minimal duplication, and extensibility.
	•	Efficiency: Appropriate algorithms, data structures, and resource use.

Scoring Rules:
	•	5 points: Excellent quality with clean, efficient, and maintainable code.
	•	4 points: Good quality, but minor readability or efficiency issues.
	•	3 points: Average quality; readable but not optimized or modular.
	•	2 points: Poor quality; lacks structure or suffers from inefficiencies.
	•	0-1 points: Unreadable, unstructured, or inefficient code.

Return this JSON:
{{
  "correctness_score": <int 0-5>,
  "purpose_alignment_score": <int 0-5>,
  "functionality_accuracy_score": <int 0-5>,
  "functionality_completeness_score": <int 0-5>,
  "code_quality_score": <int 0-5>
}}
'''


def call_openai_judge(pred: Any, gt: Any) -> tuple:
    """Call Claude, parse JSON response. Returns (parsed_json, input_tokens, output_tokens)"""
    client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY", ""))

    # modèle choisi par toi dans .env (fallback possible)
    model_name = os.environ.get("OPENAI_MODEL", "gpt-4.1")

    pred_str = json.dumps(pred) if isinstance(pred, dict) else str(pred)
    gt_str = json.dumps(gt) if isinstance(gt, dict) else str(gt)
    prompt = llm_judge_prompt.format(pred=pred_str, gt=gt_str)

    response = client.chat.completions.create(
        model=model_name,
        max_tokens=5000,
        temperature=0.0,
        messages=[{"role": "user", "content": prompt}],
        response_format={
            "type": "json_schema",
            "json_schema": {
                "name": "judge_schema",
                "schema": {
                    "type": "object",
                    "properties": {
                        "correctness_score": {"type": "number"},
                        "purpose_alignment_score": {"type": "number"},
                        "functionality_accuracy_score": {"type": "number"},
                        "functionality_completeness_score": {"type": "number"},
                        "code_quality_score": {"type": "number"},
                    },
                    "required": [
                        "correctness_score",
                        "purpose_alignment_score",
                        "functionality_accuracy_score",
                        "functionality_completeness_score",
                        "code_quality_score",
                    ],
                    "additionalProperties": False,
                },
                "strict": True,
            },
        },
    )

    # Extract text (OpenAI)
    text = response.choices[0].message.content if response.choices else ""

    # Parse JSON
    parsed = None
    if text:
        try:
            parsed = json.loads(text)
        except Exception:
            parsed = None

    # Tokens (OpenAI)
    input_tokens = getattr(response.usage, "prompt_tokens", 0) if response.usage else 0
    output_tokens = getattr(response.usage, "completion_tokens", 0) if response.usage else 0

    return parsed, input_tokens, output_tokens


def process_json_file(filepath: str, weights: Dict[str, float]) -> tuple:
    """Process JSON and evaluate. Returns (total_score, token_costs_data)"""

    with open(filepath, 'r') as f:
        content = json.load(f)

    total_score = 0
    token_costs_data = []
    excel_rows = []

    for idx, data in enumerate(content, 1):
        raw_pred = data.get("pred", {})
        pred = raw_pred if isinstance(raw_pred, dict) else {}
        gt = data.get("gt", {})

        item_index = data.get("idx", idx)

        try:
            result, input_tokens, output_tokens = call_openai_judge(pred, gt)

            if result:
                score = sum(
                    (result.get(key, 0) / 5) * weight
                    for key, weight in weights.items()
                ) * 100
            else:
                score = 0

        except Exception as e:
            print(f"Item {item_index}: Error - {e}")
            score = 0
            input_tokens = 0
            output_tokens = 0

        total_score += score

        token_costs_data.append({
            "idx": item_index,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
            "score": score
        })

        excel_rows.append({
            "index": item_index,
            **{key: (result.get(key, 0) / 5)*100 for key in weights.keys()},
            "score": score
        })

        print(f"Item {item_index}: score={score:.2f}")

    #  Create Excel file
    df = pd.DataFrame(excel_rows)

    output_fp = filepath.replace("_predictions.json", "_scores.xlsx")
    df.to_excel(output_fp, index=False)

    print(f"Scores saved to {output_fp}")

    return total_score, token_costs_data

def save_token_costs_to_excel(token_costs_data: list, output_dir: str):
    """Save costs to Excel"""
    if not token_costs_data:
        return
    
    df = pd.DataFrame(token_costs_data)
    summary = {
        "idx": "TOTAL",
        "input_tokens": df["input_tokens"].sum(),
        "output_tokens": df["output_tokens"].sum(),
        "total_tokens": df["total_tokens"].sum(),
        "score": df["score"].mean()
    }
    
    df = pd.concat([df, pd.DataFrame([summary])], ignore_index=True)
    
    excel_path = os.path.join(output_dir, "cost_eval_task1.xlsx")
    df.to_excel(excel_path, index=False, engine='openpyxl')
    
    print(f"\nToken costs: {excel_path}")
    print(f"  Total: {summary['total_tokens']} tokens")
    print(f"  Avg Score: {summary['score']:.2f}")


def main():
    parser = argparse.ArgumentParser(description="Evaluate using Claude API.")
    parser.add_argument("--input", required=True, help="JSON file path.")
    args = parser.parse_args()
    
    weights = {
        "correctness_score": 0.25,
        "purpose_alignment_score": 0.25,
        "functionality_accuracy_score": 0.20,
        "functionality_completeness_score": 0.20,
        "code_quality_score": 0.10
    }
    
    output_dir = os.path.dirname(f"{args.input}") or "."
    print(f"Processing: {args.input}")
    
    total_score, token_costs_data = process_json_file(args.input, weights)
    save_token_costs_to_excel(token_costs_data, output_dir)
    
    avg_score = total_score / len(token_costs_data) if token_costs_data else 0
    print(f"Average score: {avg_score:.2f}")


if __name__ == "__main__":
    start = time.perf_counter()
    main()
    end = time.perf_counter()
    print(f"[EVALUATION] Execution time: {end - start:.6f} seconds")
