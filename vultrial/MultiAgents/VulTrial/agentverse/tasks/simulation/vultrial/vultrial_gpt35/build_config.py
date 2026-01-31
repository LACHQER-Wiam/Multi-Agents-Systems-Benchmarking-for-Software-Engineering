import yaml
import json
from pathlib import Path

config_path = "partial_config.yaml"


Path("configs/").mkdir(parents=True, exist_ok=True)
with open('../../../../../PrimeVul_v0.1-20250102T110047Z-001/PrimeVul_v0.1/primevul_test_paired.jsonl', 'r') as json_file:
    json_list = list(json_file)
for json_str in json_list:
    result = json.loads(json_str)
    problem_string = "\n\n<code>:\n"+result["func"]

    task_config = yaml.safe_load(open(config_path))

    for agent_configs in task_config["agents"]:
        agent_configs["role_description"] += problem_string
    task_config["environment"]["id_save"] = result["idx"]
    task_config["environment"]["target"] = result["target"]

    with open("configs/"+str(result["idx"])+"-config.yaml", "w") as f:
        yaml.safe_dump(task_config, f)
