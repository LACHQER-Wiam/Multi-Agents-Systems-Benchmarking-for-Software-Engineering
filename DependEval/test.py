
import json
# from data.utils import construct_prompt
# from transformers import AutoTokenizer, AutoModelForCausalLM
# import torch
# import os

# os.environ["TOKENIZERS_PARALLELISM"] = "false"

# # Paramètres
# model_name = "microsoft/phi-2"
# language = "python"
# task = "task2"
# dataset_path = "./data/python/task2_python_final_1.json"

# # Charger le dataset
# with open(dataset_path, "r", encoding="utf-8") as f:
#     dataset = json.load(f)

# # Prendre le premier exemple
# data_item = dataset[0]

# # Construire le prompt pour task2
# prompt = construct_prompt(data_item, max_token_nums=40000, language=language, task=task)
# # print("Prompt:\n", prompt)

# # Charger modèle/tokenizer
# cache_dir = "./huggingface"
# tokenizer = AutoTokenizer.from_pretrained(model_name, cache_dir=cache_dir)
# model = AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float32, cache_dir=cache_dir)
# model.eval()

# # Génération
# inputs = tokenizer(prompt, return_tensors="pt").to(model.device)

# out = model.generate(
#         **inputs,
#         max_new_tokens=256,
#         do_sample=True,
#         temperature=0.7,
#         top_p=0.9,
#         eos_token_id=tokenizer.eos_token_id,
#         pad_token_id=tokenizer.eos_token_id,
#     )

# # Décoder uniquement la sortie générée
# gen = out[0][inputs["input_ids"].shape[1]:]
# raw_output = tokenizer.decode(gen, skip_special_tokens=True)
# print("\nRaw output:\n", raw_output)

# json_file_path = "./results/task4/python/claude-haiku-4-5-python/claude-haiku-4-5_predictions.json"
# with open(json_file_path, 'r') as f:
#         data_list = json.load(f)

# for entry in data_list:
#     idx = entry.get("idx")
#     groups = entry.get("pred", {}).get("dependency_groups", [])
#     print(f"idx {idx}: groups={groups}")


import os
import anthropic

def test_anthropic():
    client = anthropic.Anthropic(
        api_key=os.environ.get("ANTHROPIC_API_KEY")
    )

    response = client.messages.create(
        model="claude-haiku-4-5",
        max_tokens=200,
        temperature=0.7,
        messages=[
            {"role": "user", "content": "Say hello in one short sentence."}
        ]
    )

    print("Response:")
    print(response.content[0].text)

    print("\nToken usage:")
    print("Input tokens:", response.usage.input_tokens)
    print("Output tokens:", response.usage.output_tokens)

if __name__ == "__main__":
    test_anthropic()
