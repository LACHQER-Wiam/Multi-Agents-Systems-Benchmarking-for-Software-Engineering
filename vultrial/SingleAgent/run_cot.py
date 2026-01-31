from openai import OpenAI
import json
from pathlib import Path

# Modify OpenAI's API key
openai_api_key = ""
client_openai = OpenAI(
    api_key=openai_api_key,
)

def call_chatgpt(P, S_P, idx, target, model_input_run, model_input, temperature):

    completion= None
    while completion is None:
        try:
            completion = client_openai.chat.completions.create(model=model_input_run,
                                            messages=[
                                                      {"role": "system", "content": S_P},
                                                      {"role": "user", "content": P}
                                                      ],
                                            temperature=float(temperature)
                    )

        except Exception as exc:
            print(exc)
            print('Failed on %s...' % idx)
            # time.sleep(10)
            continue

        print(P)


    print(completion.choices[0].message.content)
    f = open(folder_results+model_input+"/"+str(idx)+"-"+str(target)+".txt", "w", encoding="utf-8")
    f.write(completion.choices[0].message.content)
    f.close()
    return completion.choices[0].message.content


S_P = "You are a security expert that is good at static program analysis."
COT_P = """Please analyze the following code:
```
{func}
```
Please indicate your analysis result with one of the options: 
(1) YES: A security vulnerability detected.
(2) NO: No security vulnerability. 

Make sure to include one of the options above "explicitly" (EXPLICITLY!!!) in your response.
Let's think step-by-step.
"""

model_input = "GPT-4o"
model_input_run = "gpt-4o-2024-08-06"
with open("primevul_test_paired.jsonl", 'r') as json_file:
    json_list = list(json_file)
folder_results = "../Evaluation/Results/SingleAgent/"
temperature = "0"
Path(folder_results+model_input+"/").mkdir(parents=True, exist_ok=True)
for json_str in json_list:
    result = json.loads(json_str)
    if not Path(folder_results+model_input+"/"+str(result["idx"])+"-"+str(result["target"])+".txt").is_file():
        P = COT_P.replace("{func}", result["func"])
        call_chatgpt(P, S_P, result["idx"], result["target"], model_input_run, model_input, temperature)
