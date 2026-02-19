import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

model_name = "microsoft/Phi-3.5-mini-instruct"#"microsoft/phi-4"

tokenizer = AutoTokenizer.from_pretrained(model_name)

# CPU -> float32
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    torch_dtype=torch.float32
).to("cpu")
model.eval()

prompt = "Explain overfitting in 3 bullets."

inputs = tokenizer(prompt, return_tensors="pt")

with torch.no_grad():
    out = model.generate(
        **inputs,
        max_new_tokens=150,
        do_sample=True,
        temperature=0.7,
        top_p=0.9,
        # sécurité:
        eos_token_id=tokenizer.eos_token_id,
        pad_token_id=tokenizer.eos_token_id,
    )

gen = out[0][inputs["input_ids"].shape[1]:]
print(tokenizer.decode(gen, skip_special_tokens=True))