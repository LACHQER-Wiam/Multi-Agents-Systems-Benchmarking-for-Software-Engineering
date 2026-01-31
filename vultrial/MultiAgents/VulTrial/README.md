# README

## Overview
VulTrial is built on top of AgentVerse [1].

## Requirements
Ensure you have the following installed:
- Python
- It is recommended to use a Conda environment.

### Setting up the Environment
To create and activate a Conda environment:
```bash
conda create --name agents
conda activate agents
pip install -e .
```

### Configuration
Set up your OpenAI API key:
```bash
export OPENAI_API_KEY="<YOUR_OPENAI_KEY>"
```

## Running VulTrial

### Running VulTrial Base (Using GPT-4o)
To run the base version with GPT-4o, execute:
```bash
python run_simulations.py
```

### Running VulTrial with GPT-3.5
To use GPT-3.5, execute:
```bash
python run_simulations.py vultrial_gpt35
```

## Fine-Tuning the Model
Since OpenAI's fine-tuned models cannot be shared, you need to perform the fine-tuning yourself.

1. Open the OpenAI fine-tuning page:
   [OpenAI Fine-Tuning Platform](https://platform.openai.com/finetune)
2. Create a fine-tuned model using the base model `gpt-4o-2024-08-06`.
3. Upload the dataset located at:
   ```
   InstructionTuningData/moderator.jsonl
   ```
4. Use the following fine-tuning parameters:
   - **Seed:** `1019792078`
   - **Epochs:** `3`
   - **Batch Size:** `1`
   - **Learning Rate Multiplier:** `1`
5. After fine-tuning completes, copy the output model name, which should follow this format:
   ```
   ft:gpt-4o-2024-08-06:<org>:<name>:<id>
   ```

### Updating Fine-Tuned Model References

1. Open `agentverse/llms/openai.py` and replace all instances of:
   ```
   "ft:gpt-4o-2024-08-06:personal:moderator:BAWoJsPO"
   ```
   with your fine-tuned model name.

2. Open `agentverse/tasks/simulation/vultrial/vultrial_moderator_tuned/`.
   - Replace all occurrences of:
     ```
     "ft:gpt-4o-2024-08-06:personal:moderator:BAWoJsPO"
     ```
     with your fine-tuned model name in all `.yaml` files.

## Running VulTrial with Fine-Tuned Moderator
Once the fine-tuned moderator is set up, execute:
```bash
python run_simulations.py vultrial_moderator_tuned
```

## References
[1] Chen, Weize, Yusheng Su, Jingwei Zuo, Cheng Yang, Chenfei Yuan, Chen Qian, Chi-Min Chan et al. "Agentverse: Facilitating multi-agent collaboration and exploring emergent behaviors in agents." arXiv preprint arXiv:2308.10848 2, no. 4 (2023): 6.
