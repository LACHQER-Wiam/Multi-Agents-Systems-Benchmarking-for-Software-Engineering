import json
import os
import re
import subprocess
from datasets import load_dataset

CLONE_DIR = "./repos"
OUTPUT_DIR = "./data/swebench/python"


def extract_modified_files(patch: str) -> list:
    files = []
    for line in patch.split("\n"):
        if line.startswith("diff --git a/"):
            files.append(line.split(" b/")[-1].strip())
    return files


def read_file(repo_path: str, filepath: str) -> str:
    full = os.path.join(repo_path, filepath)
    if not os.path.exists(full):
        return ""
    with open(full, "r", errors="ignore") as f:
        return f.read()


def build_content(repo_path: str, files: list) -> str:
    content = ""
    for f in files:
        code = read_file(repo_path, f)
        content += f"'{f}'\n:{code}\n"
    return content


def clone_and_checkout(repo: str, commit: str) -> str:
    repo_path = os.path.join(CLONE_DIR, repo.replace("/", "_"))
    if not os.path.exists(repo_path):
        subprocess.run(["git", "clone", f"https://github.com/{repo}", repo_path], check=True)
    subprocess.run(["git", "checkout", commit], cwd=repo_path, check=True)
    return repo_path


def build_dataset():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ds = load_dataset("princeton-nlp/SWE-bench_Lite", split="test")

    task1, task2, task4 = [], [], []

    for item in ds:
        repo = item["repo"]
        commit = item["base_commit"]
        patch = item["patch"]
        problem = item["problem_statement"]

        repo_path = clone_and_checkout(repo, commit)
        modified_files = extract_modified_files(patch)
        content = build_content(repo_path, modified_files)

        base = {
            "repo": repo,
            "content": content,
            "problem_statement": problem,
            "repo_path": repo_path,
        }

        # GT task1 — appliquer patch, lire fichiers modifiés, reset
        subprocess.run(["git", "apply", "-"], input=patch.encode(), cwd=repo_path, check=False)
        gt_me = {}
        for i, f in enumerate(modified_files, 1):
            gt_me[f"#file {i}"] = read_file(repo_path, f)
        subprocess.run(["git", "checkout", commit], cwd=repo_path, check=False)

        task1.append({
            **base,
            "called_code_segment": "",
            "invoking_code_segment": "",
            "feature_description": problem,
            "modified_complete_code": gt_me,
        })

        # GT task2 — avec guillemets simples
        task2.append({
            **base,
            "files": [f"'{f}'" for f in modified_files],
            "gt": [f"'{f}'" for f in modified_files],
        })

        # GT task4 — même format dataset normal
        task4.append({
            **base,
            "files": [{"file": f, "function": ""} for f in modified_files],
            "gt": str([[f] for f in modified_files]),
        })

    with open(f"{OUTPUT_DIR}/task1_python.json", "w") as f:
        json.dump(task1, f, indent=2)
    with open(f"{OUTPUT_DIR}/task2_python_final.json", "w") as f:
        json.dump(task2, f, indent=2)
    with open(f"{OUTPUT_DIR}/task4_python_new.json", "w") as f:
        json.dump(task4, f, indent=2)

    print(f"Done: {len(task1)} items")


if __name__ == "__main__":
    build_dataset()