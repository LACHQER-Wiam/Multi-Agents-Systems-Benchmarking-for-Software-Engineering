from langchain.agents import create_agent
from data.utils import construct_prompt
import json
import os
import pandas as pd
from pydantic import BaseModel, Field, ConfigDict
from typing import List
from langchain_anthropic import ChatAnthropic
from langchain_anthropic.middleware import AnthropicPromptCachingMiddleware, ClaudeBashToolMiddleware
# from middlewares import TokenCounterMiddleware

type_agent = "react"  # react or api

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



def define_tools(task: str):
    # Define your tools here
    if task == "task1":
        tools = []
    else:
        tools = []
    return tools


def define_middleware(task: str):
    # Define your middleware here
    if task == "task1":
        middleware = [AnthropicPromptCachingMiddleware(ttl="5m"),
                    #TokenCounterMiddleware(),
                      ClaudeBashToolMiddleware(workspace_root="/workspace")]
    else:
        middleware = [AnthropicPromptCachingMiddleware(ttl="5m"),
                    #   TokenCounterMiddleware()
                      ]
    return middleware


def process_dataset(dataset, model_name, language, temperature, task, max_token_nums, response_format):
    model = ChatAnthropic(model=model_name,)
                      #temperature=temperature,
                      #max_tokens=8192)
    
    agent = create_agent(  
        model=model,
        tools=define_tools(task),
        system_prompt="You are a softaware engineer who is an expert in understanding code dependencies and modifying code based on the dependencies.",
        response_format=response_format,
        middleware=define_middleware(task)
    )

    for idx, item in enumerate(dataset):
        prompt = construct_prompt(
            item,            
            max_token_nums=max_token_nums,
            language=language,
            task=task
        )

        result = agent.invoke(
        {"messages": [{"role": "user", "content": prompt}]})




def main(model_name: str,
        language: str,
        task: str = "task1",
        dataset_path: str = "./data",
        res_dir: str = "./results",
        batch_size: int = 1,
        temperature: float = 0.0,
        max_token_nums: int = 40000,):

    if task == "task1":
        path = os.path.join(dataset_path, language, f"{task}_{language}.json")
        response_format = {"output_format": {
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
        response_format = {"output_format": {
                    "type": "json_schema",
                    "schema":Task2Schema.model_json_schema()}}
        
    elif task == "task4":
        path = os.path.join(dataset_path, language, f"{task}_{language}_new_1.json")
        response_format = {"output_format": {
                    "type": "json_schema",
                    "schema":Task4Schema.model_json_schema()}}
    else:
        raise ValueError(f"Unknown task: {task}")

    with open(path, "r") as f:
        dataset = json.load(f)

    results = process_dataset(
            dataset,
            model_name,
            temperature,
            language,
            task,
            max_token_nums,
            response_format
        )
    
    df = pd.DataFrame(results)


    # Create output directories
    save_dir = os.path.join(res_dir, task, type_agent, f"{language}/{model_name}-{language}")
    os.makedirs(save_dir, exist_ok=True)
    name = model_name.split("/")[-1]
    evalpath = os.path.join(save_dir, f"{name}_ReAct_predictions.json")

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




