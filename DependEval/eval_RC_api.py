import json
import networkx as nx
import pandas as pd
import matplotlib.pyplot as plt
import ast
import os
import re
import argparse
import time

def find_common_prefix(paths):
    """Find the longest common directory prefix among a list of paths."""
    if not paths:
        return ""
    dirs = [os.path.dirname(path) for path in paths]
    common_dir_prefix = os.path.commonprefix(dirs)
    return common_dir_prefix


def remove_common_prefix(paths):
    """Remove the common directory prefix from paths."""
    common_dir_prefix = find_common_prefix(paths)
    if common_dir_prefix:
        common_dir_prefix += '/'
    result = []
    for path in paths:
        relative_path = path[len(common_dir_prefix):] if path.startswith(common_dir_prefix) else path
        result.append(relative_path)
    return result


def find_common_prefix2(paths):
    """Find the longest common prefix among a list of paths."""
    if not paths:
        return ""
    return os.path.commonprefix(paths)


def remove_common_prefix_across_groups(groups):
    """Remove common prefix across all groups."""
    all_paths = [path for group in groups for path in group]
    common_prefix = find_common_prefix2(all_paths)
    updated_paths = [path[len(common_prefix):] for path in all_paths]

    result = []
    idx = 0
    for group in groups:
        group_size = len(group)
        result.append(updated_paths[idx:idx + group_size])
        idx += group_size
    return result


def build_graph_inverted(call_chains):
    """
    Build a directed graph from reversed call chains.
    """
    try:
        pattern = r"\[\[.*?\]\]"
        match = re.search(pattern, str(call_chains).replace('\n', '').replace(' ', ''), re.DOTALL)
        if match:
            call_chains = match[0]

        call_chains = ast.literal_eval(call_chains)

        if (
            isinstance(call_chains, list)
            and len(call_chains) == 1
            and isinstance(call_chains[0], list)
            and isinstance(call_chains[0][0], list)
        ):
            call_chains = call_chains[0]

    except Exception as e:
        print("Error parsing call_chains:", e)
        call_chains = []

    G = nx.DiGraph()

    for chain in call_chains:
        for i in range(1, len(chain)):
            try:
                G.add_edge(chain[i], chain[i - 1])
            except:
                print("Error in chain:", chain)

    return G


def calculate_f1(precision, recall):
    if precision + recall == 0:
        return 0
    return 2 * (precision * recall) / (precision + recall)


def evaluate_graph_similarity(pred_graph, gt_graph):
    pred_nodes = set(pred_graph.nodes())
    gt_nodes = set(gt_graph.nodes())

    pred_edges = set(pred_graph.edges())
    gt_edges = set(gt_graph.edges())

    true_positive_nodes = len(pred_nodes.intersection(gt_nodes))
    precision_nodes = true_positive_nodes / len(pred_nodes) if pred_nodes else 0
    recall_nodes = true_positive_nodes / len(gt_nodes) if gt_nodes else 0
    f1_nodes = calculate_f1(precision_nodes, recall_nodes)

    true_positive_edges = len(pred_edges.intersection(gt_edges))
    precision_edges = true_positive_edges / len(pred_edges) if pred_edges else 0
    recall_edges = true_positive_edges / len(gt_edges) if gt_edges else 0
    f1_edges = calculate_f1(precision_edges, recall_edges)

    return {
        "node_f1_score": f1_nodes,
        "edge_f1_score": f1_edges
    }

def evaluate_single_item(entry):
    """
    Evaluate one JSON entry and return combined F1 score.
    """

    pred_chains = entry.get('pred', [])
    gt_chains = entry.get('gt', [])

    pred_graph = build_graph_inverted(pred_chains.get("dependency_groups", []))
    gt_graph = build_graph_inverted(gt_chains)

    similarity = evaluate_graph_similarity(pred_graph, gt_graph)

    node_f1 = similarity["node_f1_score"]
    edge_f1 = similarity["edge_f1_score"]

    combined_f1 = 0.15 * node_f1 + 0.85 * edge_f1

    return combined_f1


def evaluate_json_file(json_file_path):
    """
    Evaluate a single JSON file and save scores to Excel.
    """

    with open(json_file_path, 'r') as f:
        list_pred = json.load(f)

    rows = []

    for entry in list_pred:
        idx = entry.get("idx")
        try:
            score = evaluate_single_item(entry)
        except Exception as e:
            print(f"Error at idx {idx}: {e}")
            score = 0.0

        rows.append({
            "idx": idx,
            "dependency_groups": entry.get("pred", {}).get("dependency_groups", []),
            "gt": entry.get("gt", []),
            "score": score
        })

        print(f"idx {idx}: score={score:.4f}")

    df = pd.DataFrame(rows)

    output_fp = json_file_path.replace(".json", "_scores.xlsx")
    df.to_excel(output_fp, index=False)

    print(f"Results saved to {output_fp}")

    return df


def main():
    parser = argparse.ArgumentParser(description="Process JSON files and compute scores.")
    parser.add_argument("--input", required=True, help="Path to the JSON file.")
    args = parser.parse_args()

    evaluate_json_file(args.input)


if __name__ == "__main__":
    start = time.perf_counter()
    main()
    end = time.perf_counter()
    print(f"[EVALUATION] Execution time: {end - start:.6f} seconds")
