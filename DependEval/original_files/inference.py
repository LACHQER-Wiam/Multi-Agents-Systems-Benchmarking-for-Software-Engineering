"""Local inference adapter for use with run.py.

This mirrors the behavior of `inference_api.py` but uses a provided
`inference_func(prompt, top_p, temperature)` callable (as in `run.py`).
It computes input/output token counts (using the tokenizer from `run.py`
if available, or by loading one from `model_name`), adapts the output
schema for tasks (task1/task2/task4), and writes results to a single
JSON file (not JSONL). It also saves token costs to an Excel file.
"""
import os
import json
import asyncio
import pandas as pd
from typing import Callable
from transformers import AutoTokenizer
from DependEval.data.utils import construct_prompt


def count_tokens(tokenizer, text: str) -> int:
    if not text:
        return 0
    try:
        return len(tokenizer.encode(text))
    except Exception:
        return len(text.split())


async def call_inference(inference_func: Callable, prompt: str, top_p: float, temperature: float):
    try:
        return await asyncio.to_thread(lambda: inference_func(prompt, top_p, temperature))
    except Exception as e:
        print(f"Inference error: {e}")
        return ""


def get_tokenizer(model_name: str):
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    if tokenizer.pad_token is None and tokenizer.eos_token is not None:
        tokenizer.pad_token = tokenizer.eos_token
    return tokenizer


def adapt_output(task: str, raw_output: str):
    try:
        parsed = json.loads(raw_output)
    except Exception:
        parsed = None

    if task == "task1":
        required = [
            "called_code_segment",
            "invoking_code_segment",
            "feature_description",
            "modified_complete_code",
        ]
        if isinstance(parsed, dict) and all(k in parsed for k in required):
            return parsed
        return {k: "" for k in required} | {"modified_complete_code": raw_output}

    if task == "task2":
        return raw_output
        # if isinstance(parsed, list):
        #     return parsed
        # return [s.strip() for s in raw_output.replace("[", "").replace("]", "").split(",") if s.strip()]

    if task == "task4":
        if isinstance(parsed, list):
            return parsed
        return [[s.strip() for s in raw_output.replace("[", "").replace("]", "").split(",") if s.strip()]]

    return raw_output


def get_dataset_path(dataset_path: str, language: str, task: str):
    if task == "task1":
        return os.path.join(dataset_path, language, f"{task}_{language}.json")
    if task == "task2":
        return os.path.join(dataset_path, language, f"{task}_{language}_final_1.json")
    if task == "task4":
        return os.path.join(dataset_path, language, f"{task}_{language}_new_1.json")
    raise ValueError(f"Unknown task: {task}")


def main(
    model_name: str,
    language: str,
    task: str,
    inference_func: Callable,
    dataset_path: str = "./data",
    res_dir: str = "./results",
    temperature: float = 0.0,
    top_p: float = 0.95,
    max_token_nums: int = 40000,
):
    assert inference_func is not None, "inference_func must be provided"

    # Load dataset
    path = get_dataset_path(dataset_path, language, task)
    with open(path, "r", encoding="utf-8") as f:
        dataset = json.load(f)

    # Setup output directory
    safe_model_name = model_name.replace("/", "-")
    save_dir = os.path.join(res_dir, task, f"{safe_model_name}-{language}")
    os.makedirs(save_dir, exist_ok=True)
    output_json_path = os.path.join(save_dir, f"{safe_model_name}.json")
    output_excel_path = os.path.join(save_dir, f"{safe_model_name}.xlsx")

    tokenizer = get_tokenizer(model_name)

    async def process(idx, item):
        prompt = construct_prompt(
            item,
            max_token_nums=max_token_nums,
            language=language,
            task=task,
        )

        raw_output = await call_inference(inference_func, prompt, top_p, temperature)
        pred = adapt_output(task, raw_output)

        input_tokens = count_tokens(tokenizer, prompt)
        output_tokens = count_tokens(tokenizer, raw_output)
        total_tokens = input_tokens + output_tokens

        gt = item.get("modified_complete_code" if task == "task1" else "gt", "")

        return {
            "idx": idx,
            "pred": pred,
            "gt": gt,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": total_tokens,
        }

    async def run_all():
        return await asyncio.gather(*(process(i, d) for i, d in enumerate(dataset)))

    results = asyncio.run(run_all())

    # Save Excel
    df = pd.DataFrame(results)
    df.to_excel(output_excel_path, index=False)

    # Save JSON
    with open(output_json_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=4)

    print(f"Saved predictions to: {output_json_path}")
    print(f"Saved token stats to: {output_excel_path}")

    return output_json_path
