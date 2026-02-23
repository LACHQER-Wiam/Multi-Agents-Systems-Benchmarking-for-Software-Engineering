import argparse
import os
import inference_api
import inference_ReAct
import agent_cast
import time


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run model evaluation via Anthropic API.")
    parser.add_argument("--type_agent", type=str, required=True, help="Anthropic model name")
    parser.add_argument("--model_name", type=str, required=True, help="Anthropic model name")
    parser.add_argument("--language", type=str, required=True)
    parser.add_argument("--task", type=str, default="task1")
    parser.add_argument("--dataset_path", type=str, default="./data")
    parser.add_argument("--res_dir", type=str, default="./results")
    parser.add_argument("--batch_size", type=int, default=(1))
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--top_p", type=float, default=0.1)
    parser.add_argument("--max_token_nums", type=int, default=40000)
    args = parser.parse_args()

    start = time.perf_counter()

    if args.type_agent == "api":
        eval_path = inference_api.main(
            model_name=args.model_name,
            language=args.language,
            task=args.task,
            dataset_path=args.dataset_path,
            res_dir=args.res_dir,
            batch_size=args.batch_size,
            temperature=args.temperature,
            max_token_nums=args.max_token_nums,
        )
    elif args.type_agent == "react":
        eval_path = inference_ReAct.main(
            model_name=args.model_name,
            language=args.language,
            task=args.task,
            dataset_path=args.dataset_path,
            res_dir=args.res_dir,
            batch_size=args.batch_size,
            temperature=args.temperature,
            max_token_nums=args.max_token_nums,
        )
    elif args.type_agent == "cast":
        # Generic CAST-style ReAct agent — input-format independent.
        # Loads files from disk (any language, any structure) and runs the
        # dependency / call-chain analysis agent.
        import glob as _glob
        pattern = os.path.join(args.dataset_path, args.language, "**", "*.py")
        file_paths = _glob.glob(pattern, recursive=True)
        if not file_paths:
            # Fallback: any file under the language folder
            pattern = os.path.join(args.dataset_path, args.language, "**", "*.*")
            file_paths = _glob.glob(pattern, recursive=True)
        print(f"[CAST] Analysing {len(file_paths)} file(s) in {args.language}/")
        request = agent_cast.load_files_from_disk(
            file_paths,
            query="Identify all dependency relationships and call chains in this project.",
        )
        result = agent_cast.run_agent(request, model_name=args.model_name, temperature=args.temperature)
        save_dir = os.path.join(args.res_dir, args.task, "cast", args.language)
        os.makedirs(save_dir, exist_ok=True)
        out_path = os.path.join(save_dir, f"{args.model_name.replace('/', '-')}_cast_result.json")
        import json as _json
        with open(out_path, "w") as fh:
            _json.dump(result.model_dump(), fh, indent=2)
        print(f"[CAST] Results saved to {out_path}")
        eval_path = out_path


    end = time.perf_counter()

    print(f"[PREDICTION] Execution time: {end - start:.6f} seconds")
    # print(f"Evaluation complete. Results at: {eval_path}")
