from inference import main
import pandas as pd
import os
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch
import argparse

os.environ["TOKENIZERS_PARALLELISM"] = "false"

parser = argparse.ArgumentParser(description="Run model evaluation with specified parameters.")
parser.add_argument("--model_name", type=str, required=True)
parser.add_argument("--language", type=str, required=True)
parser.add_argument("--task", type=str, default="task1")
parser.add_argument("--dataset_path", type=str, default="./data")
parser.add_argument("--res_dir", type=str, default="./results")
parser.add_argument("--batch_size", type=int, default=1)
parser.add_argument("--temperature", type=float, default=0.2)
parser.add_argument("--top_p", type=float, default=0.95)
parser.add_argument("--max_token_nums", type=int, default=40000)
args = parser.parse_args()
cache_dir = "./huggingface"


model = AutoModelForCausalLM.from_pretrained(
args.model_name,
torch_dtype=torch.float32,
# device_map="auto",
cache_dir=cache_dir
).to("cpu")
tokenizer = AutoTokenizer.from_pretrained(args.model_name,cache_dir=cache_dir)
tokenizer.pad_token = tokenizer.eos_token

def inference_func(prompt,top_p,temperature):
    # Simple prompt -> tokenization -> generation pipeline inspired by test_cle.py
    text = prompt

    # Ensure model in eval mode
    model.eval()

    # Tokenize and move tensors to model device
    model_inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True)
    model_inputs = {k: v.to(model.device) for k, v in model_inputs.items()}

    gen_kwargs = dict(
        **model_inputs,
        max_new_tokens=512,
        do_sample=True,
        top_p=float(max(0.0, min(1.0, top_p))),
        temperature=max(0.0, float(temperature)),
        eos_token_id=getattr(tokenizer, "eos_token_id", None),
        pad_token_id=getattr(tokenizer, "pad_token_id", None),

    )

    with torch.no_grad():
        out_ids = model.generate(**gen_kwargs)

    # Slice to only the newly generated tokens for the first batch element
    input_len = model_inputs["input_ids"].shape[1]
    new_ids = out_ids[0, input_len:]

    response = tokenizer.decode(new_ids, skip_special_tokens=True)
    return response



if __name__ == "__main__":
    eval_path = main(
        model_name=args.model_name,
        language=args.language,
        task=args.task,
        dataset_path=args.dataset_path,
        res_dir=args.res_dir,
        # batch_size=args.batch_size,
        temperature=args.temperature,
        top_p=args.top_p,
        max_token_nums=args.max_token_nums,
        inference_func=inference_func
    )