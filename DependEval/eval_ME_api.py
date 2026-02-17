"""
eval_ME_api.py - Simple evaluation using Claude API.
Tracks token usage and saves cost metrics to Excel.
"""

import json
import argparse
import os
import pandas as pd
from typing import Any, Dict
import anthropic

llm_judge_prompt = '''
Gt: {gt}
Pred: {pred}

Evaluate Pred against Gt on these 5 criteria. Return JSON with scores only.

Return this JSON:
{{
  "correctness_score": <int 0-5>,
  "purpose_alignment_score": <int 0-5>,
  "functionality_accuracy_score": <int 0-5>,
  "functionality_completeness_score": <int 0-5>,
  "code_quality_score": <int 0-5>
}}
'''


def call_claude_judge(pred: Any, gt: Any) -> tuple:
    """Call Claude, parse JSON response. Returns (parsed_json, input_tokens, output_tokens)"""
    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))
    
    pred_str = json.dumps(pred) if isinstance(pred, dict) else str(pred)
    gt_str = json.dumps(gt) if isinstance(gt, dict) else str(gt)
    prompt = llm_judge_prompt.format(pred=pred_str, gt=gt_str)
    
    response = client.messages.create(
        model="claude-opus-4-6",
        max_tokens=256,
        messages=[{"role": "user", "content": prompt}],
        extra_headers={"anthropic-beta": "structured-outputs-2025-11-13"},
        extra_body={
            "output_format": {
                "type": "json_schema",
                "schema": {
                    "type": "object",
                    "properties": {
                        "correctness_score": {"type": "number"},
                        "purpose_alignment_score": {"type": "number"},
                        "functionality_accuracy_score": {"type": "number"},
                        "functionality_completeness_score": {"type": "number"},
                        "code_quality_score": {"type": "number"}
                    },
                    "required": ["correctness_score", "purpose_alignment_score", 
                                "functionality_accuracy_score", "functionality_completeness_score",
                                "code_quality_score"],
                    "additionalProperties": False
                }
            }
        }
    )
    
    # Extract text
    text = response.content[0].text if response.content else ""
    
    # Parse JSON (like inference_api.py)
    parsed = None
    if text:
        try:
            parsed = json.loads(text)
        except Exception:
            pass
    
    input_tokens = response.usage.input_tokens
    output_tokens = response.usage.output_tokens
    
    return parsed, input_tokens, output_tokens


def process_json_file(filepath: str, weights: Dict[str, float]) -> tuple:
    """Process JSON and evaluate. Returns (total_score, token_costs_data)"""
    with open(filepath, 'r') as f:
        content = json.load(f)
    
    total_score = 0
    token_costs_data = []
    updated_data = []
    
    for idx, data in enumerate(content, 1):
        raw_pred = data.get("pred", {})
        pred = raw_pred if isinstance(raw_pred, dict) else {}
        gt = data.get("gt", {})
        
        try:
            result, input_tokens, output_tokens = call_claude_judge(pred, gt)
            
            if result:
                # Calculate score
                score = sum(
                    (result.get(key, 0) / 5) * weight 
                    for key, weight in weights.items()
                ) * 100
                
                data["score"] = score
                total_score += score
                
                token_costs_data.append({
                    "idx": data.get("idx", idx),
                    "input_tokens": input_tokens,
                    "output_tokens": output_tokens,
                    "total_tokens": input_tokens + output_tokens,
                    "score": score
                })
                print(f"Item {idx}: score={score:.2f}")
            else:
                data["score"] = 0
                token_costs_data.append({
                    "idx": data.get("idx", idx),
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "total_tokens": 0,
                    "score": 0
                })
        
        except Exception as e:
            print(f"Item {idx}: Error - {e}")
            data["score"] = 0
            token_costs_data.append({
                "idx": data.get("idx", idx),
                "input_tokens": 0,
                "output_tokens": 0,
                "total_tokens": 0,
                "score": 0
            })
        
        updated_data.append(data)
    
    # Save scored results
    output_fp = filepath.replace(".json", "_scored.json")
    with open(output_fp, 'w') as f:
        json.dump(updated_data, f, ensure_ascii=True, indent=4)
    
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
    
    excel_path = os.path.join(output_dir, "cost_eval_ME.xlsx")
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
    
    output_dir = os.path.dirname(args.input) or "."
    print(f"Processing: {args.input}")
    
    total_score, token_costs_data = process_json_file(args.input, weights)
    save_token_costs_to_excel(token_costs_data, output_dir)
    
    avg_score = total_score / len(token_costs_data) if token_costs_data else 0
    print(f"Average score: {avg_score:.2f}")


if __name__ == "__main__":
    main()
