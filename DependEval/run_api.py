import argparse
import os
from inference import main
import anthropic

# simple wrapper factory that calls the Anthropic API using the `anthropic` package

def make_anthropic_inference(model_name: str):
    def inference(prompt: str, top_p: float, temperature: float) -> str:
        # expecting ANTHROPIC_API_KEY in environment
        client = anthropic.Client(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))
        # build prompt using the human/AI delimiters
        response = client.messages.create(
            model=model_name,
            # prompt=full_prompt,
            max_tokens=8192,
            temperature=temperature,
            # top_p=top_p,
            messages=[{"role": "user", "content": prompt}]
        )
        # the field is `completion` according to package docs
        return response.content[0].text
    return inference


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run model evaluation via Anthropic API.")
    parser.add_argument("--model_name", type=str, required=True, help="Anthropic model name (e.g. claude-2.1)")
    parser.add_argument("--language", type=str, required=True)
    parser.add_argument("--task", type=str, default="task1")
    parser.add_argument("--dataset_path", type=str, default="./data")
    parser.add_argument("--res_dir", type=str, default="./results")
    parser.add_argument("--batch_size", type=int, default=1)
    parser.add_argument("--temperature", type=float, default=0.2)
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
        inference_func=make_anthropic_inference(args.model_name),
    )
    # you can call evaluation scripts on eval_path afterward
