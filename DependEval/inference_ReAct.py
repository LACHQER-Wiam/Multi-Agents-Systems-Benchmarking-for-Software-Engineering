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

from middlewares import TokenCounterMiddleware
from model_factory import create_llm
from tools import BashWorkspaceTool

# Répertoire dans lequel l'outil bash exécute les commandes (éditer fichiers, lancer scripts).
WORKSPACE_ROOT = os.environ.get("WORKSPACE_ROOT", "/workspace")

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


# -----------------------------------------------------------------------------
# Helpers : extraction prédiction / ground truth
# -----------------------------------------------------------------------------

def _extract_pred_from_agent_result(invoke_result: dict) -> Any:
    """
    Extrait la prédiction finale depuis le retour de agent.invoke().

    Le résultat contient une clé "messages". On prend le dernier message (assistant),
    on en extrait le contenu texte, et on tente un parse JSON pour avoir un dict
    quand le modèle renvoie du structured output.

    Le dict renvoyé est compatible avec les trois evals :
    - task1 (ME) : dict avec called_code_segment, invoking_code_segment, etc.
    - task2 (DR) : dict avec list_dependencies → eval_DR_api
    - task4 (RC) : dict avec dependency_groups → eval_RC_api
    Si le JSON est invalide, on renvoie la chaîne brute (eval_ME_api gère les deux).
    """
    messages = invoke_result.get("messages", [])
    if not messages:
        return ""

    last = messages[-1]
    content = getattr(last, "content", None) if not isinstance(last, dict) else last.get("content")

    if content is None:
        return ""

    # Contenu peut être une liste de blocs (ex. [{"type": "text", "text": "..."}])
    if isinstance(content, list):
        parts = [b.get("text", b) if isinstance(b, dict) else str(b) for b in content]
        text = "".join(p for p in parts if isinstance(p, str))
    else:
        text = str(content).strip()

    if not text:
        return ""

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def _get_ground_truth(item: dict, task: str) -> Any:
    """Ground truth pour un item du dataset, selon la tâche (aligné sur inference_api)."""
    if task == "task1":
        return item.get("modified_complete_code", "")
    return item.get("gt", "")


def define_tools(task: str) -> list:
    """
    Liste des outils disponibles pour l'agent selon la tâche.

    - task1 : outil bash dans le workspace (éditer fichiers, lancer des commandes).
    - task2 / task4 : pas d'outils.
    """
    if task == "task1":
        tools = [BashWorkspaceTool(workspace_root=WORKSPACE_ROOT)]
        return tools
    else:
        tools = []
    return tools
 

def define_middleware(task: str, token_counter: Optional[TokenCounterMiddleware] = None) -> list:
    """
    Liste des middlewares appliqués à l'agent (compatibles OpenAI).

    - TokenCounterMiddleware : log des tokens par appel + cumul total.
    token_counter: instance partagée pour lire les totaux (reset_totals, total_input/output_tokens).
    """
    tc = token_counter if token_counter is not None else TokenCounterMiddleware()
    return [tc]


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
    """
    Lance l'agent ReAct sur chaque item du dataset.

    provider: "openai", "anthropic", "google" — API LLM utilisée.
    Retourne une liste de dicts {"idx", "pred", "gt"} au format attendu par
    les scripts d'éval (eval_DR_api, eval_ME_api, eval_RC_api).
    """
    token_counter = TokenCounterMiddleware()
    model = create_llm(
        provider=provider,
        model_name=model_name,
        temperature=temperature,
        max_tokens=max_token_nums,
    )
    agent = create_agent(
        model=model,
        tools=define_tools(task),
        system_prompt=(
            "You are a software engineer who is an expert in understanding "
            "code dependencies and modifying code based on the dependencies."
        ),
        response_format=response_format,
        middleware=define_middleware(task, token_counter),
    )

    results = []
    for idx, item in enumerate(dataset):
        token_counter.reset_totals()
        prompt = construct_prompt(
            item,
            max_token_nums=max_token_nums,
            language=language,
            task=task,
        )
        try:
            result = agent.invoke({"messages": [{"role": "user", "content": prompt}]})
            pred = _extract_pred_from_agent_result(result)
            # Force le format attendu par les evals (évite 'str' object has no attribute get)
            if task == "task4" and not isinstance(pred, dict):
                pred = {"dependency_groups": []}

            if task == "task2" and not isinstance(pred, dict):
                pred = {"list_dependencies": []}
        except Exception as e:
            print(f"Error at idx {idx}: {e}")
            pred = ""

        gt = _get_ground_truth(item, task)
        results.append({
            "idx": idx,
            "pred": pred,
            "gt": gt,
            "input_tokens": token_counter.total_input_tokens,
            "output_tokens": token_counter.total_output_tokens,
            #liste des appels LLM pour cet idx
            "calls": token_counter.calls,
            "num_calls": len(token_counter.calls),
        })
        print(f"Prediction for idx {idx} done (total tokens: {token_counter.total_input_tokens + token_counter.total_output_tokens}).")

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




