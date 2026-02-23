from utils.metric import exact_match_score, normalize_answer
import json
import re
import os
import argparse
import pandas as pd
import time

def task2_match(text: str):
    match = re.search(r"\[.*?\]", str(text))
    return match.group() if match else ""


def evaluate_single_item(data: dict) -> float:
    """
    Evaluate a single JSON item.
    Returns 1 if exact match average == 1, else 0.
    """

    pred_raw = data.get("pred")
    gt = data.get("gt")

    if pred_raw is None or gt is None:
        return 0.0

    # pred est déjà une liste
    pred_list = pred_raw.get("list_dependencies", [])
    if not isinstance(pred_list, list) or len(pred_list) == 0:
        return 0.0

    # gt est une liste avec guillemets simples à retirer
    if isinstance(gt, list):
        gt_list = [g.strip("'\"") for g in gt]
    else:
        return 0.0

    if len(gt_list) == 0:
        return 0.0

    try:
        pred_set = set(exact_match_score(p, p) and p for p in pred_list)  
        # Plus simple — utilise normalize_answer directement
        from utils.metric import normalize_answer
        pred_set = set(normalize_answer(p) for p in pred_list)
        gt_set = set(normalize_answer(g) for g in gt_list)
        return 1.0 if pred_set == gt_set else 0.0
    except Exception:
        return 0.0


def process_all_files_in_directory(filepath):
    """
    Analyse un fichier JSON unique,
    calcule le score pour chaque entrée,
    et sauvegarde un Excel avec colonnes: idx, score.
    """

    print(f"Processing: {filepath}")

    with open(filepath, "r", encoding="utf-8") as f:
        content = json.load(f)

    rows = []

    for i, data in enumerate(content, 1):
        idx = data.get("idx", i)

        try:
            score = evaluate_single_item(data)  # par item
        except Exception as e:
            print(f"Error at idx {idx}: {e}")
            score = 0

        rows.append({
            "idx": idx,
            "dependency_groups": data.get("pred", {}).get("list_dependencies", []),  #.
            "gt": data.get("gt", []),
            "score": score
        })
        print(data.get("list_dependencies", []))

        print(f"idx {idx}: score={score:.2f}")

    df = pd.DataFrame(rows)

    output_fp = filepath.replace(".json", "_scores.xlsx")
    df.to_excel(output_fp, index=False)

    print(f"Results saved to {output_fp}")

    return df


def main():
    parser = argparse.ArgumentParser(description="Process JSON files and compute scores.")
    parser.add_argument("--input", required=True, help="Directory containing JSON files.")
    args = parser.parse_args()

    filepath = args.input

    process_all_files_in_directory(filepath)


if __name__ == "__main__":
    start = time.perf_counter()
    main()
    end = time.perf_counter()
    print(f"[EVALUATION] Execution time: {end - start:.6f} seconds")
