import argparse
import os
from inference_api import main


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run model evaluation via Anthropic API.")
    parser.add_argument("--model_name", type=str, required=True, help="Anthropic model name (e.g. claude-opus-4-6)")
    parser.add_argument("--language", type=str, required=True)
    parser.add_argument("--task", type=str, default="task1")
    parser.add_argument("--dataset_path", type=str, default="./data")
    parser.add_argument("--res_dir", type=str, default="./results")
    parser.add_argument("--batch_size", type=int, default=1)
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--top_p", type=float, default=0.95)
    parser.add_argument("--max_token_nums", type=int, default=40000)
    args = parser.parse_args()

    eval_path = main(
        model_name=args.model_name,
        language=args.language,
        task=args.task,
        dataset_path=args.dataset_path,
        res_dir=args.res_dir,
        batch_size=args.batch_size,
        temperature=args.temperature,
        top_p=args.top_p,
        max_token_nums=args.max_token_nums,
    )
    # print(f"Evaluation complete. Results at: {eval_path}")
