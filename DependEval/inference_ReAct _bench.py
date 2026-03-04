"""
Inférence ReAct pour DependEval : un agent par tâche (task1=ME, task2=DR, task4=RC).

Remplace l'appel API simple (inference_api.py) par un agent ReAct avec outils optionnels
et middlewares. Produit le même format de sortie (JSON avec idx, pred, gt) pour les evals.
"""

from langchain.agents import create_agent
from data.utils import construct_prompt
import json
import os
import pandas as pd
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Any, Optional
from workspace_tools import ReadFileTool, ListDirTool, SearchInFilesTool, WriteFileTool, ExtractImportsTool

from middlewares import TokenCounterMiddleware
from model_factory import create_llm, get_response_format, SCHEMAS
os.environ["LANGCHAIN_TRACING_V2"] = "false"

# Répertoire dans lequel l'outil bash exécute les commandes (éditer fichiers, lancer scripts).
WORKSPACE_ROOT = os.environ.get("WORKSPACE_ROOT", "/workspace")

type_agent = "react_bench" 

# class Task2Schema(BaseModel):
#     model_config = ConfigDict(extra="forbid")

#     list_dependencies: List[str] = Field(
#         description="Dependency relationship between files ['file1.py', 'file2.py']"
#     )

# class Task4Schema(BaseModel):
#     model_config = ConfigDict(extra="forbid")

#     dependency_groups: List[List[str]] = Field(
#         description="List of dependency groups such as [['file1.py', 'file2.py'], ['file3.py']]"
#     )


# -----------------------------------------------------------------------------
# Helpers : extraction prédiction / ground truth
# -----------------------------------------------------------------------------

def _extract_pred_from_agent_result(invoke_result: dict) -> Any:
    structured = invoke_result.get("structured_response")
    if structured is not None:
        if hasattr(structured, "model_dump"):
            return structured.model_dump()
        return structured
    # fallback messages
    messages = invoke_result.get("messages", [])
    if not messages:
        return ""
    last = messages[-1]
    content = getattr(last, "content", None) if not isinstance(last, dict) else last.get("content")
    if not content:
        return ""
    try:
        return json.loads(str(content).strip())
    except Exception:
        return str(content).strip()


def _get_ground_truth(item: dict, task: str) -> Any:
    """Ground truth pour un item du dataset, selon la tâche (aligné sur inference_api)."""
    if task == "task1":
        return item.get("modified_complete_code", "")
    return item.get("gt", "")


def define_tools(task: str, workspace_root: str = WORKSPACE_ROOT) -> list:
    """
    Liste des outils disponibles pour l'agent selon la tâche.

    - task1 : outil bash dans le workspace (éditer fichiers, lancer des commandes).
    - task2 / task4 : pas d'outils.
    """
    if task == "task1":
        return [
            ReadFileTool(workspace_root=workspace_root),
            ListDirTool(workspace_root=workspace_root),
            SearchInFilesTool(workspace_root=workspace_root),
            WriteFileTool(workspace_root=workspace_root),
        ]
    elif task in ("task2", "task4"):
        return [
            ReadFileTool(workspace_root=workspace_root),
            ExtractImportsTool(workspace_root=workspace_root),
        ]
    return []
 

def define_middleware(task: str, token_counter: Optional[TokenCounterMiddleware] = None) -> list:
    """
    Liste des middlewares appliqués à l'agent.

    - TokenCounterMiddleware : log des tokens par appel + cumul total.
    token_counter: instance partagée pour lire les totaux (reset_totals, total_input/output_tokens).
    """
    tc = token_counter if token_counter is not None else TokenCounterMiddleware()
    return [tc]

def get_system_prompt(task: str, schema_str: str) -> str:
    base = "You are a software engineer expert in analyzing and modifying code.\n"
    
    if task == "task1":
        return base + (
            "Your job is to implement a requested feature by modifying existing code.\n"
            "RULES:\n"
            "- called_code_segment: the EXACT original function/class being modified\n"
            "- invoking_code_segment: the EXACT code that calls it\n"
            "- feature_description: one sentence describing the feature\n"
            "- modified_complete_code: ALL modified files, each prefixed with filename\n"
            "  Format: '// filename.js\\n<code>\\n// filename2.js\\n<code>'\n"
            "- Use MINIMAL changes, stay close to existing code style\n"
            "- Do NOT add features not explicitly requested\n"
            "- Do NOT over-engineer the solution\n"
            f"Always respond ONLY with a valid JSON object matching this schema:\n{schema_str}"
        )
    
    elif task == "task2":
        return base + (
        "Your job is to identify ALL files that are involved in dependency relationships.\n"
        "RULES:\n"
        "- list_dependencies: list of file paths involved in dependencies\n"
        "- Each item is a single file path string, NOT a pair\n"
        "- Include every file that imports OR is imported by another file\n"
        "- Do NOT use 'file_a -> file_b' format\n"
        "- Do NOT invent files that don't exist in the code\n"
        f"Always respond ONLY with a valid JSON object matching this schema:\n{schema_str}"
    )
    
    elif task == "task4":
        return base + (
            "Your job is to identify dependency CHAIN groups between files.\n"
            "RULES:\n"
            "- Each group is a chain: [file_A, file_B, file_C] means A imports B which imports C\n"
            "- Only include DIRECT dependencies found in the code (imports, requires)\n"
            "- Do NOT invent dependencies that don't exist\n"
            "- A file with no dependencies is its own group: ['file.js']\n"
            "- Do NOT merge separate independent chains into one long chain\n"
            "- Each unique chain path must be its own group\n"
            f"Always respond ONLY with a valid JSON object matching this schema:\n{schema_str}"
        )
    
    return base + f"Always respond ONLY with a valid JSON object matching this schema:\n{schema_str}"


def process_dataset(
    dataset: list,
    model_name: str,
    language: str,
    temperature: float,
    task: str,
    max_token_nums: int,
    response_format: dict,
    provider: str = "openai",
) -> list:
    token_counter = TokenCounterMiddleware()
    model = create_llm(
        provider=provider,
        model_name=model_name,
        temperature=temperature,
        max_tokens=max_token_nums,
    )
    schema_str = json.dumps(SCHEMAS.get(task, {}), indent=2)

    results = []
    for idx, item in enumerate(dataset):
        token_counter.reset_totals()
        workspace = item.get("repo_path", WORKSPACE_ROOT)  # ← dynamique par item

        agent = create_agent(  # ← dans la boucle, pas avant
            model=model,
            tools=define_tools(task, workspace_root=workspace),
            system_prompt=get_system_prompt(task, schema_str),
            middleware=define_middleware(task, token_counter),
            response_format=response_format,
        )

        prompt = construct_prompt(
            item,
            max_token_nums=max_token_nums,
            language=language,
            task=task,
        )
        try:
            result = agent.invoke({"messages": [{"role": "user", "content": prompt}]})
            pred = _extract_pred_from_agent_result(result)
            if task == "task4" and not isinstance(pred, dict):
                pred = {"dependency_groups": []}
            if task == "task2" and not isinstance(pred, dict):
                pred = {"list_dependencies": []}
        except Exception as e:
            print(f"Error at idx {idx}: {e}")
            pred = {}
            result = {"messages": []}

        input_tokens = 0
        output_tokens = 0
        calls = []
        for msg in result.get("messages", []):
            usage = getattr(msg, "usage_metadata", None)
            if usage:
                call_input = usage.get("input_tokens", 0)
                call_output = usage.get("output_tokens", 0)
                input_tokens += call_input
                output_tokens += call_output
                calls.append({
                    "call_num": len(calls) + 1,
                    "input_tokens": call_input,
                    "output_tokens": call_output,
                    "total_tokens": call_input + call_output,
                })
        token_counter.total_input_tokens = input_tokens
        token_counter.total_output_tokens = output_tokens
        token_counter.calls = calls

        gt = _get_ground_truth(item, task)
        results.append({
            "idx": idx,
            "pred": pred,
            "gt": gt,
            "input_tokens": token_counter.total_input_tokens,
            "output_tokens": token_counter.total_output_tokens,
            "calls": token_counter.calls,
            "num_calls": len(token_counter.calls),
        })
        print(f"Prediction for idx {idx} done (total tokens: {input_tokens + output_tokens}).")

    return results




def main(
    model_name: str,
    language: str,
    task: str = "task1",
    dataset_path: str = "./data",
    res_dir: str = "./results",
    batch_size: int = 1,
    temperature: float = 0.0,
    max_token_nums: int = 40000,
    provider: str = "openai",
) -> str:
    """
    Point d'entrée : charge le dataset, lance l'agent ReAct, sauvegarde les
    prédictions au format JSON attendu par les scripts d'éval.

    provider: "openai", "anthropic", "google" — API LLM utilisée.
    """
    path_map = {
    "task1": f"{task}_{language}.json",
    "task2": f"{task}_{language}_final.json",
    "task4": f"{task}_{language}_new.json",
    }
    if task not in path_map:
        raise ValueError(f"Unknown task: {task}")

    path = os.path.join(dataset_path, language, path_map[task])
    response_format = get_response_format(task, provider)

    with open(path, "r", encoding="utf-8") as f:
        dataset = json.load(f)
    dataset = dataset[:5] #for testing

    results = process_dataset(
            dataset,
            model_name,
            language,
            temperature,
            task,
            max_token_nums,
            response_format,
            provider=provider,
        )
    
    df = pd.DataFrame(results)
    df["total_tokens"] = df["input_tokens"] + df["output_tokens"]

    # Create output directories
    save_dir = os.path.join(res_dir, task, type_agent, f"{language}/{model_name}-{language}")
    os.makedirs(save_dir, exist_ok=True)
    name = model_name.split("/")[-1]
    evalpath = os.path.join(save_dir, f"{name}_ReAct_predictions.json")

    # Save token costs to Excel (like inference_api)
    # Construire la table détaillée des appels LLM
    calls_rows = []
    for row in results:
        idx = row["idx"]
        for c in row.get("calls", []):
            calls_rows.append({
                "idx": idx,
                "call_num": c["call_num"],
                "input_tokens": c["input_tokens"],
                "output_tokens": c["output_tokens"],
                "total_tokens": c["total_tokens"],
            })

    calls_df = pd.DataFrame(calls_rows)

    # Supprimer la colonne brute 'calls' de la sheet principale (optionnel mais propre)
    df_main = df.drop(columns=["calls"], errors="ignore")

    # Écriture Excel avec 2 sheets
    cost_file = os.path.join(save_dir, f"cost_predictions_{name}.xlsx")
    with pd.ExcelWriter(cost_file, engine="openpyxl") as writer:
        df_main.to_excel(writer, index=False, sheet_name="per_item_totals")
        calls_df.to_excel(writer, index=False, sheet_name="per_llm_call")

    print(f"Saved token costs to: {cost_file}")

    total_input = int(df["input_tokens"].sum())
    total_output = int(df["output_tokens"].sum())
    total_all = int(df["total_tokens"].sum())
    print(f"\n--- SUMMARY ---")
    print(f"Total rows: {len(df)}")
    print(f"Total input tokens: {total_input}")
    print(f"Total output tokens: {total_output}")
    print(f"Total tokens: {total_all}")

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




