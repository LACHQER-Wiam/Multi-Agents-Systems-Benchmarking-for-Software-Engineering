# README

## Overview
This code is adapted from the GPTLens replication package [1] with an update to the prompt, replacing "smart contract" with "code" for a more general-purpose approach.

## Requirements
Ensure you have the following installed:
- Python
- OpenAI Python library

### Installation
To install the required OpenAI library, run:
```bash
pip install openai
```

### Configuration
Set up your OpenAI API key in `src/model.py`:
```python
OPENAI_API = "<YOUR_OPENAI_KEY>"
```

## Running the Code
Navigate to the `src/` folder to execute the scripts.

### Running the Auditor Agent
To run the auditor agent, execute:
```bash
python run_auditor.py --backend=gpt-4o --temperature=0.7 --topk=3 --num_auditor=2 --data_dir="../data/PrimeVul_clean"
```

### Running the Critic Agent
To run the critic agent, execute:
```bash
python run_critic.py --backend=gpt-4o --temperature=0 --auditor_dir="auditor_gpt-4o_0.7_top3_2" --num_critic=1
```

### Calculating the Final Score
To compute the final score from the critic's evaluation, execute:
```bash
python run_ranker.py --auditor_dir="auditor_gpt-4o_0.7_top3_2" --critic_dir="critic_gpt-4o_0.0_1" --strategy="default"
```

### Getting the Final Results
To determine whether the final results fall into the "vulnerability" or "benign" category (if at least one vulnerability highlighted by the ranker has a score of at least 5), execute:
```bash
python change_to_primevul --auditor_dir="auditor_gpt-4o_0.7_top3_2" --critic_dir="critic_gpt-4o_0.0_1" --strategy="default"
```

## Output Location
The logs are stored in `logs/src/`. The final results can be found in:
```
src/logs/auditor_gpt-4o_0.7_top3_2/critic_gpt-4o_0.0_1/ranker_default/primevul_results
```

## Reference
[1] Hu, Sihao, Tiansheng Huang, Fatih Ilhan, Selim Furkan Tekin, and Ling Liu. "Large language model-powered smart contract vulnerability detection: New perspectives." In *2023 5th IEEE International Conference on Trust, Privacy and Security in Intelligent Systems and Applications (TPS-ISA)*, pp. 297-306. IEEE, 2023.

