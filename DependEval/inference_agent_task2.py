"""Multi-agent system for Task2 (dependency analysis).

Three agents work together to analyze file dependencies:
1. Agent1: Generates initial dependency list with justification
2. Agent2: Reviews Agent1's response, provides counter-analysis and criticism
3. Agent3: Synthesizes all information to provide final dependency list

Uses LangChain with Anthropic API and structured outputs.
"""

import os
import json
import asyncio
import argparse
import pandas as pd
from datetime import datetime
from typing import List, Tuple
from pydantic import BaseModel, Field, ConfigDict
import anthropic
from DependEval.data.utils_api import construct_prompt
import time


# ============================================================================
# SCHEMA DEFINITIONS
# ============================================================================

class Agent1Output(BaseModel):
    """Agent1: Initial dependency analysis"""
    model_config = ConfigDict(extra="forbid")
    
    dependency_list: List[str] = Field(
        description="List of files in dependency order, e.g., ['file1.py', 'file2.py', 'file3.py']"
    )
    justification: str = Field(
        description="Detailed explanation of why these dependencies exist"
    )


class Agent2Output(BaseModel):
    """Agent2: Review and counter-analysis"""
    model_config = ConfigDict(extra="forbid")
    
    dependency_list: List[str] = Field(
        description="Agent2's own analysis of dependencies"
    )
    strengths: str = Field(
        description="Points that are correct or strong in Agent1's response"
    )
    weaknesses: str = Field(
        description="Points that are incorrect, missing, or weak in Agent1's response"
    )
    counter_arguments: str = Field(
        description="Alternative perspectives or challenges to Agent1's analysis"
    )


class Agent3Output(BaseModel):
    """Agent3: Final synthesis"""
    model_config = ConfigDict(extra="forbid")
    
    final_dependency_list: List[str] = Field(
        description="Final consensus dependency list based on analysis from Agent1 and Agent2"
    )
    reasoning: str = Field(
        description="Explanation of how Agent3 synthesized the information from both agents"
    )
    confidence: str = Field(
        description="Assessment of confidence in the final answer"
    )


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _get_schema_json(model_class: type) -> dict:
    """Get JSON schema for a Pydantic model."""
    return model_class.model_json_schema()


async def _call_agent(
    client: anthropic.AsyncAnthropic,
    prompt: str,
    schema: type,
    model_name: str = "claude-opus-4-1",
    temperature: float = 0.0,
    max_tokens: int = 2048,
) -> Tuple[dict, dict]:
    """Call Anthropic API with structured output and return parsed response + usage.
    
    Returns:
        (parsed_response, usage_dict) where parsed_response is the validated output
        and usage_dict contains input_tokens and output_tokens
    """
    
    schema_json = _get_schema_json(schema)
    
    response = await client.messages.create(
        model=model_name,
        max_tokens=max_tokens,
        temperature=temperature,
        messages=[{"role": "user", "content": prompt}],
        extra_headers={"anthropic-beta": "structured-outputs-2025-11-13"},
        extra_body={
            "output_format": {
                "type": "json_schema",
                "schema": schema_json
            }
        },
    )
    
    # Extract text
    text = ""
    if response.content:
        text = response.content[0].text
    
    # Parse JSON
    parsed = {}
    if text:
        try:
            parsed = json.loads(text)
        except Exception as e:
            print(f"Failed to parse JSON from agent: {e}")
            parsed = {}
    
    # Extract usage
    usage = {
        "input_tokens": getattr(response.usage, "input_tokens", 0),
        "output_tokens": getattr(response.usage, "output_tokens", 0),
    }
    
    return parsed, usage


# ============================================================================
# AGENT 1: Initial Analysis
# ============================================================================

async def agent1_initial_analysis(
    client: anthropic.AsyncAnthropic,
    code_content: str,
    filenames: List[str],
    model_name: str = "claude-opus-4-1",
) -> Tuple[dict, dict]:
    """Agent 1: Generate initial dependency list with justification.
    
    Args:
        client: Anthropic async client
        code_content: The code snippets to analyze
        filenames: List of filenames being analyzed
        model_name: Model to use
    
    Returns:
        (agent1_output, usage) where agent1_output is validated Agent1Output
    """
    
    files_str = ', '.join(filenames)
    
    prompt = f"""You are a code dependency analysis expert. Analyze the following code snippets and determine the dependency relationships between the files.

Files: {files_str}

Code:
```
{code_content}
```

Your task:
1. Identify which files depend on which other files
2. Return the dependency chain where each file depends on the previous one
3. Provide a clear justification for your analysis

Output the files in dependency order, e.g., if file2 depends on file1 and file3 depends on file2, output: ["file1.py", "file2.py", "file3.py"]

IMPORTANT:
- Do NOT include files that have no dependencies
- A list must contain at least two filenames
- Use the exact filenames as provided
- Do NOT include parent folders
"""
    
    output, usage = await _call_agent(
        client,
        prompt,
        Agent1Output,
        model_name=model_name,
    )
    
    return output, usage


# ============================================================================
# AGENT 2: Review and Counter-Analysis
# ============================================================================

async def agent2_review_analysis(
    client: anthropic.AsyncAnthropic,
    code_content: str,
    filenames: List[str],
    agent1_output: dict,
    model_name: str = "claude-opus-4-1",
) -> Tuple[dict, dict]:
    """Agent 2: Review Agent1's analysis and provide counter-analysis.
    
    Args:
        client: Anthropic async client
        code_content: The code snippets to analyze
        filenames: List of filenames being analyzed
        agent1_output: The output from Agent1
        model_name: Model to use
    
    Returns:
        (agent2_output, usage) where agent2_output is validated Agent2Output
    """
    
    files_str = ', '.join(filenames)
    
    agent1_deps = agent1_output.get("dependency_list", [])
    agent1_justif = agent1_output.get("justification", "")
    
    prompt = f"""You are a critical code reviewer analyzing file dependencies. 

Files: {files_str}

Code:
```
{code_content}
```

Agent 1's Analysis:
- Dependency List: {json.dumps(agent1_deps)}
- Justification: {agent1_justif}

Your task:
1. Independently analyze the code and determine the correct dependency relationships
2. Identify the STRENGTHS in Agent 1's analysis (what they got right)
3. Identify the WEAKNESSES in Agent 1's analysis (what they missed or misunderstood)
4. Provide COUNTER-ARGUMENTS or alternative perspectives
5. Output your own dependency list based on your independent analysis
6. Provide detailed explanations for your points
7. If the answer of the Agent 1 is correct, your dependency list should match theirs. If not, explain the discrepancies.

Be thorough and critical. Point out specific code segments that support or contradict Agent 1's findings.

IMPORTANT:
- Do NOT include files that have no dependencies
- A list must contain at least two filenames
- Use the exact filenames as provided
- Do NOT include parent folders
"""
    
    output, usage = await _call_agent(
        client,
        prompt,
        Agent2Output,
        model_name=model_name,
    )
    
    return output, usage


# ============================================================================
# AGENT 3: Final Synthesis
# ============================================================================

async def agent3_final_synthesis(
    client: anthropic.AsyncAnthropic,
    code_content: str,
    filenames: List[str],
    agent1_output: dict,
    agent2_output: dict,
    model_name: str = "claude-opus-4-1",
) -> Tuple[dict, dict]:
    """Agent 3: Synthesize analyses from Agent1 and Agent2.
    
    Args:
        client: Anthropic async client
        code_content: The code snippets to analyze
        filenames: List of filenames being analyzed
        agent1_output: Output from Agent1
        agent2_output: Output from Agent2
        model_name: Model to use
    
    Returns:
        (agent3_output, usage) where agent3_output is validated Agent3Output
    """
    
    files_str = ', '.join(filenames)
    
    agent1_deps = agent1_output.get("dependency_list", [])
    agent1_justif = agent1_output.get("justification", "")
    
    agent2_deps = agent2_output.get("dependency_list", [])
    agent2_strengths = agent2_output.get("strengths", "")
    agent2_weaknesses = agent2_output.get("weaknesses", "")
    agent2_counter = agent2_output.get("counter_arguments", "")
    
    prompt = f"""You are a senior code architect tasked with making the final decision on file dependencies.

Files: {files_str}

Code:
```
{code_content}
```

Agent 1's Analysis:
- Dependency List: {json.dumps(agent1_deps)}
- Justification: {agent1_justif}

Agent 2's Analysis:
- Dependency List: {json.dumps(agent2_deps)}
- Identified Strengths in Agent1: {agent2_strengths}
- Identified Weaknesses in Agent1: {agent2_weaknesses}
- Counter-Arguments: {agent2_counter}

Your task:
1. Carefully consider both analyses
2. Evaluate the code evidence for each perspective
3. Synthesize both viewpoints to determine the most accurate dependency list
4. Provide your reasoning for the final answer
5. Assess your confidence level in the final answer

Balance both perspectives and use code evidence to support your decision.

IMPORTANT:
- Do NOT include files that have no dependencies
- A list must contain at least two filenames
- Use the exact filenames as provided
- Do NOT include parent folders
- Return ONLY one single dependency chain, not multiple chains
"""
    
    output, usage = await _call_agent(
        client,
        prompt,
        Agent3Output,
        model_name=model_name,
    )
    
    return output, usage


# ============================================================================
# MAIN ORCHESTRATION FOR BATCH PROCESSING
# ============================================================================

async def process_dataset_multi_agent(
    dataset: List[dict],
    model_name: str,
    batch_size: int = 1,
    temperature: float = 0.0,
    max_token_nums: int = 40000,
    log_file = None,
) -> List[dict]:
    """Process entire dataset with multi-agent system.
    
    Args:
        dataset: List of data points
        model_name: Anthropic model name
        batch_size: Batch size for processing
        temperature: Temperature for API calls
        max_token_nums: Max tokens constraint
        log_file: File object for logging
    
    Returns:
        List of result dicts with all agent outputs and tokens
    """
    
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    client = anthropic.AsyncAnthropic(api_key=api_key)
    
    sem = asyncio.Semaphore(batch_size)
    results = []
    
    async def worker(idx, data_item):
        """Process a single example with all 3 agents."""
        
        # Construct prompt (same as inference_api.py)
        prompt = construct_prompt(
            data_item,
            max_token_nums=max_token_nums,
            language="python",
            task="task2"
        )
        
        files = data_item.get("files", [])
        code_content = data_item.get("content", "")
        gt = data_item.get("gt", "")
        
        async with sem:
            try:
                # Run all 3 agents
                agent1_output, agent1_usage = await agent1_initial_analysis(
                    client, code_content, files, model_name
                )
                
                agent2_output, agent2_usage = await agent2_review_analysis(
                    client, code_content, files, agent1_output, model_name
                )
                
                agent3_output, agent3_usage = await agent3_final_synthesis(
                    client, code_content, files, agent1_output, agent2_output, model_name
                )
                
                # Aggregate tokens
                total_input = (
                    agent1_usage['input_tokens'] + 
                    agent2_usage['input_tokens'] + 
                    agent3_usage['input_tokens']
                )
                total_output = (
                    agent1_usage['output_tokens'] +
                    agent2_usage['output_tokens'] +
                    agent3_usage['output_tokens']
                )
                
                result = {
                    "idx": idx,
                    "agent1_output": agent1_output,
                    "agent2_output": agent2_output,
                    "agent3_output": agent3_output,
                    "agent1_input_tokens": agent1_usage['input_tokens'],
                    "agent1_output_tokens": agent1_usage['output_tokens'],
                    "agent2_input_tokens": agent2_usage['input_tokens'],
                    "agent2_output_tokens": agent2_usage['output_tokens'],
                    "agent3_input_tokens": agent3_usage['input_tokens'],
                    "agent3_output_tokens": agent3_usage['output_tokens'],
                    "total_input_tokens": total_input,
                    "total_output_tokens": total_output,
                    "total_tokens": total_input + total_output,
                    "gt": gt,
                    "list_dependencies": agent3_output.get("final_dependency_list", []),
                }
                
                log_msg = f"[{idx}] Completed - Agent1 tokens: {agent1_usage['input_tokens']}/{agent1_usage['output_tokens']}, Agent2: {agent2_usage['input_tokens']}/{agent2_usage['output_tokens']}, Agent3: {agent3_usage['input_tokens']}/{agent3_usage['output_tokens']}, Total: {total_input}/{total_output}"
                print(log_msg)
                if log_file:
                    log_file.write(log_msg + "\n")
                    log_file.flush()
                    
            except Exception as e:
                error_msg = f"[{idx}] Error: {str(e)}"
                print(error_msg)
                if log_file:
                    log_file.write(error_msg + "\n")
                    log_file.flush()
                
                result = {
                    "idx": idx,
                    "agent1_output": {},
                    "agent2_output": {},
                    "agent3_output": {},
                    "agent1_input_tokens": 0,
                    "agent1_output_tokens": 0,
                    "agent2_input_tokens": 0,
                    "agent2_output_tokens": 0,
                    "agent3_input_tokens": 0,
                    "agent3_output_tokens": 0,
                    "total_input_tokens": 0,
                    "total_output_tokens": 0,
                    "total_tokens": 0,
                    "gt": data_item.get("gt", ""),
                    "list_dependencies": [],
                    "error": str(e),
                }
            
            results.append(result)
    
    # Create workers
    tasks = [asyncio.create_task(worker(i, d)) for i, d in enumerate(dataset)]
    if tasks:
        await asyncio.gather(*tasks)
    
    return results


def main(
    model_name: str,
    language: str = "python",
    task: str = "task2",
    dataset_path: str = "./data",
    res_dir: str = "./results",
    logs_dir: str = "./logs",
    batch_size: int = 1,
    temperature: float = 0.0,
    max_token_nums: int = 40000,
):
    """Main entry point for multi-agent batch processing."""
    
    # Load dataset (same as inference_api.py for task2)
    path = os.path.join(dataset_path, language, f"{task}_{language}_final.json")
    
    with open(path, "r") as f:
        dataset = json.load(f)
    
    print(f"Loaded {len(dataset)} examples from {path}")
    
    # Create output directories
    save_dir = os.path.join(res_dir, task, language, f"{model_name.split('/')[-1]}_3agents")
    os.makedirs(save_dir, exist_ok=True)
    os.makedirs(logs_dir, exist_ok=True)
    
    # Extract model name for file naming
    model_name_clean = model_name.split("/")[-1]
    
    # Create log file
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file_path = os.path.join(
        logs_dir, 
        f"{model_name_clean}_{language}_task{task[4:]}_multi_agent.txt"
    )
    
    print(f"Logging to: {log_file_path}")
    print(f"Results will be saved to: {save_dir}\n")
    
    # Run async processing with logging
    with open(log_file_path, "w") as log_file:
        log_file.write(f"Multi-Agent Task2 Analysis\n")
        log_file.write(f"Model: {model_name}\n")
        log_file.write(f"Language: {language}\n")
        log_file.write(f"Dataset: {path}\n")
        log_file.write(f"Started: {datetime.now().isoformat()}\n")
        log_file.write("=" * 80 + "\n\n")
        log_file.flush()
        
        results = asyncio.run(
            process_dataset_multi_agent(
                dataset,
                model_name,
                batch_size=batch_size,
                temperature=temperature,
                max_token_nums=max_token_nums,
                log_file=log_file,
            )
        )
        
        log_file.write("\n" + "=" * 80 + "\n")
        log_file.write(f"Completed: {datetime.now().isoformat()}\n")
    
    # Convert results to DataFrame for analysis
    df = pd.DataFrame(results)
    
    # Save token costs to Excel
    cost_file = os.path.join(
        save_dir,
        f"{model_name_clean}_{language}_multi_agent_cost.xlsx"
    )
    cost_df = df[[
        "idx",
        "agent1_input_tokens",
        "agent1_output_tokens",
        "agent2_input_tokens",
        "agent2_output_tokens",
        "agent3_input_tokens",
        "agent3_output_tokens",
        "total_input_tokens",
        "total_output_tokens",
        "total_tokens",
    ]].copy()
    cost_df.to_excel(cost_file, index=False)
    print(f"\nSaved cost breakdown to: {cost_file}")
    
    # Print summary statistics
    total_input = df["total_input_tokens"].sum()
    total_output = df["total_output_tokens"].sum()
    avg_tokens_per_example = (total_input + total_output) / len(df) if len(df) > 0 else 0
    
    print(f"\n--- SUMMARY ---")
    print(f"Total examples: {len(df)}")
    print(f"Total input tokens: {total_input}")
    print(f"Total output tokens: {total_output}")
    print(f"Total tokens: {total_input + total_output}")
    print(f"Average tokens per example: {avg_tokens_per_example:.2f}")
    
    # Save predictions JSON
    predictions = []
    for _, row in df.iterrows():
        try:
            obj = {
                "idx": int(row["idx"]),
                "agent1_prediction": row["agent1_output"].get("dependency_list", []) if isinstance(row["agent1_output"], dict) else [],
                "agent2_prediction": row["agent2_output"].get("dependency_list", []) if isinstance(row["agent2_output"], dict) else [],
                "list_dependencies": row["list_dependencies"] if isinstance(row["list_dependencies"], list) else [],
                "gt": row["gt"],
                "total_tokens": int(row["total_tokens"]),
            }
            json.dumps(obj)  # Validate
            predictions.append(obj)
        except (TypeError, ValueError) as e:
            print(f"Warning: Could not serialize idx {row['idx']}: {e}")
            predictions.append({
                "idx": int(row["idx"]),
                "agent1_prediction": [],
                "agent2_prediction": [],
                "list_dependencies": [],
                "gt": "",
                "total_tokens": 0,
            })
    
    # Save predictions JSON
    pred_file = os.path.join(
        save_dir,
        f"{model_name_clean}_{language}_multi_agent_predictions.json"
    )
    with open(pred_file, "w", encoding="utf-8") as f:
        json.dump(predictions, f, ensure_ascii=True, indent=4)
    print(f"Saved predictions to: {pred_file}")
    
    return pred_file


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run multi-agent Task2 analysis via Anthropic API.")
    parser.add_argument("--model_name", type=str, default="claude-haiku-4-5", help="Anthropic model name")
    parser.add_argument("--language", type=str, default="python", help="Programming language")
    parser.add_argument("--dataset_path", type=str, default="./data", help="Path to dataset directory")
    parser.add_argument("--res_dir", type=str, default="./results", help="Results directory")
    parser.add_argument("--logs_dir", type=str, default="./logs", help="Logs directory")
    parser.add_argument("--batch_size", type=int, default=1, help="Batch size")
    parser.add_argument("--temperature", type=float, default=0.0, help="Temperature for API")
    parser.add_argument("--max_token_nums", type=int, default=50000, help="Max tokens")
    
    args = parser.parse_args()

    start = time.perf_counter()
    
    main(
        model_name=args.model_name,
        language=args.language,
        task="task2",
        dataset_path=args.dataset_path,
        res_dir=args.res_dir,
        logs_dir=args.logs_dir,
        batch_size=args.batch_size,
        temperature=args.temperature,
        max_token_nums=args.max_token_nums,
    )
    end = time.perf_counter()

    print(f"[PREDICTION] Execution time: {end - start:.6f} seconds")
