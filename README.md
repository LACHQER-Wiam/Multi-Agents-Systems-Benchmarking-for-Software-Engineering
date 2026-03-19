# Multi-Agents-Systems-Benchmarking-for-Software-Engineering
This Capstone project (as part of the Master 2 in Data Science at Institut Polytechnique) aims to explore and compare different multi-agent system architectures for software engineering applications.

<h1><img src="https://github.com/ink7-sudo/DependEval/blob/finalversion/assets/logo.png?raw=true" width="32" style="vertical-align:middle; margin-right:8px;">DependEval: Benchmarking LLMs for Repository Dependency Understanding</h1>

The repository contains the data and evaluation code for ACL 2025 Findings paper ["DependEval: Benchmarking LLMs for Repository Dependency Understanding"](https://arxiv.org/pdf/2503.06689)

## Introduction

We introduce **DependEval**, a hierarchical benchmark for evaluating LLMs on repository-level code understanding across 8 programming languages. 

DependEval comprises 2,683 curated repositories across 8 programming languages, and evaluates models on three hierarchical tasks: ***Dependency Recognition***, ***Repository Construction***, and ***Multi-file Editing***. 

<img width="1432" alt="abs" src="https://github.com/ink7-sudo/DependEval/blob/finalversion/assets/taskcase.png?raw=true">

Our findings highlight key challenges in applying LLMs to large-scale development, and lay the groundwork for future improvements in repository-level understanding.

<img width="1432" alt="abs" src="https://github.com/ink7-sudo/DependEval/blob/finalversion/assets/radar.png?raw=true">

## How to Run the single API call mode

```bash
# Implement your model in the `inference_func` inside run.py
# Then run the following commands for automatic inference and evaluation

conda create -n dependeval python=3.10 -y
conda activate dependeval
pip install -r requirements.txt
bash run.sh
```


# How to test inferece AtoA 
Start the server in the first terminal :
```bash
python3 -m  utils.AtoA_architecture_stream_1 --task task4 --language python
```
To visualise the agent card, run this command : 
```bash
curl http://127.0.0.1:10008/.well-known/agent.json
```

In the second terminal, run the following command to analyze all the data: 
```bash 
bash run.sh 
``` 
And to analyze one specific example, you can use curl command : 
```bash 
curl -N http://127.0.0.1:10008 \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "message/stream",
    "params": {
      "message": {
        "role": "user",
        "parts": [
          {
            "type": "text",
            "text": "### Repository
                    got-your-back

                    ### Project Description
                    GYB is a command-line tool for backing up Gmail messages to a local computer.

                    ### Project Function
                    Utilizes Gmail's API over HTTPS to securely download and store emails locally, offering installation options for Linux, MacOS, and Windows.

                    ### Files
                    - got-your-back/fmbox.py: This library provides functionality to read and manipulate mbox files sequentially, allowing extraction, modification, and removal of email headers, as well as iterating through messages in an mbox file.
                    - got-your-back/gyb.py: This script is a command-line tool for backing up and restoring Gmail messages. It supports various actions such as backup, restore, count, purge, and label management, and integrates with Google APIs for Gmail and Google Workspace services. The tool uses OAuth 2.0 for authentication and supports both user accounts and service accounts.
                    - got-your-back/labellang.py: Unable to read file content."
          }
        ],
        "messageId": "1"
      },
      "metadata": {}
    }
  }
``` 






## Citation
Feel free to cite us
```bibtex
@misc{du2025dependevalbenchmarkingllmsrepository,
      title={DependEval: Benchmarking LLMs for Repository Dependency Understanding}, 
      author={Junjia Du and Yadi Liu and Hongcheng Guo and Jiawei Wang and Haojian Huang and Yunyi Ni and Zhoujun Li},
      year={2025},
      eprint={2503.06689},
      archivePrefix={arXiv},
      primaryClass={cs.SE},
      url={https://arxiv.org/abs/2503.06689}, 
}
```
