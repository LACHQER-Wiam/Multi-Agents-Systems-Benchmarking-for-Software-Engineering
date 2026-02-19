"""Simple async inference intended for use via run_api.

Calls the Anthropic API in parallel using asyncio.
Stores results in a pandas DataFrame and saves cost metrics to Excel.
Entry point: main() – compatible with run_api.py interface.
"""

import os
import json
import asyncio
import argparse
import pandas as pd
from data.utils import construct_prompt
import anthropic
from pydantic import BaseModel, Field, ConfigDict
from typing import List


class Task2Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")

    list_dependencies: List[str] = Field(
        description="Dependency relationship between files ['file1.py', 'file2.py']"
    )

class Task4Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dependency_groups: List[List[str]] = Field(
        description="List of dependency groups such as [['file1.py', 'file2.py'], ['file3.py']]"
    )


async def _call_anthropic(model_name: str, prompt: str, temperature: float, extra_body: dict):
    """Call Claude API and return (parsed_response, usage_dict).

    When using the structured outputs beta feature the response text
    should contain JSON that conforms to the provided schema. This helper
    attempts to parse the text with ``json.loads``; if parsing fails the
    raw text is returned instead so callers are robust.
    """
    client = anthropic.Client(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))

    def sync():
        return client.messages.create(
            model=model_name,
            max_tokens=8192,
            temperature=temperature,
            messages=[{"role": "user", "content": prompt}],
            # Enable the beta feature
            extra_headers={
                "anthropic-beta": "structured-outputs-2025-11-13"
            },
            extra_body=extra_body)

    resp = await asyncio.to_thread(sync)
    
    # Extract text from response
    text = ""
    if getattr(resp, "content", None):
        try:
            text = resp.content[0].text
            # print(f"text {text}")
        except Exception:
            pass

    # Try to parse the text as JSON so callers get a structured object
    parsed = None
    if text:
        try:
            parsed = json.loads(text)
            # print(f"parsed {parsed}")
        except Exception:
            # Fallback to raw text if parsing fails
            parsed = text
    else:
        parsed = text

    # Extract usage (tokens): response.usage has input_tokens and output_tokens
    usage = {}
    if getattr(resp, "usage", None) is not None:
        if isinstance(resp.usage, dict):
            usage = resp.usage
        else:
            # Convert object to dict
            try:
                usage = resp.usage.__dict__
            except Exception:
                usage = {}
    
    return parsed, usage



async def _process_dataset(dataset, model_name, temperature, batch_size, language, task, max_token_nums, extra_body):
    """Run inference over all examples in parallel. Return list of result dicts."""
    
    sem = asyncio.Semaphore(batch_size)
    results = []

    async def worker(idx, data_item):
        """Process a single example."""
        prompt = construct_prompt(data_item, max_token_nums=max_token_nums, language=language, task=task)
        
        async with sem:
            try:
                pred, usage = await _call_anthropic(model_name, prompt, temperature, extra_body=extra_body)
            except Exception as e:
                print(f"Error at idx={idx}: {e}")
                pred = ""
                usage = {}

            # pred may already be a dict if the model returned valid JSON
            # otherwise it's a string; downstream code writes it out with
            # json.dump so both are fine.

            # Extract input tokens
            input_tokens = 0
            if "input_tokens" in usage:
                input_tokens = usage["input_tokens"]
            elif "prompt_tokens" in usage:
                input_tokens = usage["prompt_tokens"]

            # Extract output tokens
            output_tokens = 0
            if "completion_tokens" in usage:
                output_tokens = usage["completion_tokens"]
            elif "output_tokens" in usage:
                output_tokens = usage["output_tokens"]

            # Get ground truth
            if task == "task1":
                gt = data_item.get("modified_complete_code", "")
            else:
                gt = data_item.get("gt", "")

            results.append({
                "idx": idx,
                "pred": pred,
                "gt": gt,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
            })
            print(f"prediction for idx {idx} done")

    # Create all workers
    tasks = [asyncio.create_task(worker(i, d)) for i, d in enumerate(dataset)]
    if tasks:
        await asyncio.gather(*tasks)

    return results



def main(
    model_name: str,
    language: str,
    task: str = "task1",
    dataset_path: str = "./data",
    res_dir: str = "./results",
    batch_size: int = 1,
    temperature: float = 0.0,
    top_p: float = 0.95,
    max_token_nums: int = 40000,
):
    """Main entry point. Runs async inference and saves results."""
    
    # Load dataset
    if task == "task1":
        path = os.path.join(dataset_path, language, f"{task}_{language}.json")
        extra_body = {"output_format": {
                    "type": "json_schema",
                    "schema": {
                "type": "object",
                "properties": {
                    "called_code_segment": {"type": "string", "description": "#file 1 segment being invoked (excluding `import`)"},
                    "invoking_code_segment": {"type": "string", "description": "#file 2 segment invoking #file 1 (excluding `import`)"},
                    "feature_description": {"type": "string", "description": "Description of the new feature"},
                    #"detailed_feature_description": {"type": "string", "description": "General explanation of the modification approach"},
                    "modified_complete_code": {"type": "string", "description": "Provide the complete code with the required modifications. Output the modified code snippets. Use comments like #Modify for modified parts and #New for newly added parts to indicate whether the change is an addition or modification."}
                },
                "required": [
                    "called_code_segment",
                    "invoking_code_segment",
                    "feature_description",
                    #"detailed_feature_description",
                    "modified_complete_code"
                ],
                "additionalProperties": False
                }
                }
            }
    elif task == "task2":
        path = os.path.join(dataset_path, language, f"{task}_{language}_final.json")
        extra_body = {"output_format": {
                    "type": "json_schema",
                    "schema":Task2Schema.model_json_schema()}}
        
    elif task == "task4":
        path = os.path.join(dataset_path, language, f"{task}_{language}_new.json")
        extra_body = {"output_format": {
                    "type": "json_schema",
                    "schema":Task4Schema.model_json_schema()}}
    else:
        raise ValueError(f"Unknown task: {task}")

    with open(path, "r") as f:
        dataset = json.load(f)

    print(f"Loaded {len(dataset)} examples from {path}")

    # Create output directories
    save_dir = os.path.join(res_dir, task, f"{language}/{model_name}-{language}")
    os.makedirs(save_dir, exist_ok=True)
    name = model_name.split("/")[-1]
    evalpath = os.path.join(save_dir, f"{name}_predictions.json")

    print(f"Results directory: {save_dir}")

    # Run async inference
    results = asyncio.run(
        _process_dataset(
            dataset,
            model_name,
            temperature,
            batch_size,
            language,
            task,
            max_token_nums,
            extra_body
        )
    )


    # Convert results to DataFrame
    df = pd.DataFrame(results)
    
    # Compute cost metrics per row
    df["total_tokens"] = df["input_tokens"] + df["output_tokens"]
    
    # Save cost breakdown to Excel in cost/ subfolder
    # cost_dir = os.path.join(save_dir, "cost")
    # os.makedirs(cost_dir, exist_ok=True)
    cost_file = os.path.join(save_dir, f"cost_predictions_{name}.xlsx")
    df.to_excel(cost_file, index=False)
    print(f"Saved token costs to: {cost_file}")

    # Print summary statistics
    total_input = df["input_tokens"].sum()
    total_output = df["output_tokens"].sum()
    total_all = df["total_tokens"].sum()
    print(f"\n--- SUMMARY ---")
    print(f"Total rows: {len(df)}")
    print(f"Total input tokens: {total_input}")
    print(f"Total output tokens: {total_output}")
    print(f"Total tokens: {total_all}")

    # # Write predictions to JSONL (one JSON object per line)
    # # Overwrite to avoid stale data
    # with open(evalpath, "w", encoding="utf-8") as fout:
    #     for _, row in df.iterrows():
    #         try:
    #             obj = {
    #                 "idx": int(row["idx"]),
    #                 "pred": row["pred"],
    #                 "gt": row["gt"],
    #             }
    #             # Use default json.dumps() which handles escaping correctly
    #             line_str = json.dumps(obj, ensure_ascii=True)
    #             # Validate that the line is valid JSON
    #             json.loads(line_str)
    #             fout.write(line_str + "\n")
    #         except (TypeError, ValueError) as e:
    #             print(f"Warning: Could not serialize idx {row['idx']}: {e}")
    #             # Write empty prediction as fallback
    #             fallback = {"idx": int(row["idx"]), "pred": "", "gt": ""}
    #             fout.write(json.dumps(fallback, ensure_ascii=True) + "\n")

    data = []

    for _, row in df.iterrows():
        try:
            obj = {
                "idx": int(row["idx"]),
                "pred": row["pred"],
                "gt": row["gt"],
            }
            # Validate object
            json.dumps(obj)
            data.append(obj)

        except (TypeError, ValueError) as e:
            print(f"Warning: Could not serialize idx {row['idx']}: {e}")
            # Fallback object
            fallback = {
                "idx": int(row["idx"]),
                "pred": "",
                "gt": ""
            }
            data.append(fallback)

    # Write entire list at once
    with open(evalpath, "w", encoding="utf-8") as fout:
        json.dump(data, fout, ensure_ascii=True, indent=4)
    
    print(f"Saved predictions to: {evalpath}")

    return evalpath
