In the initial phase, we established a baseline using a One Completion methodology. The goal was to determine if state-of-the-art Large Language Models (LLMs) could solve the Dependency Recognition (DR) task by simply reading project context and predicting the dependency order in a one response.
We evaluated two categories of models:

    Open-Source (via Ollama): Llama 3.2 (3B) and DeepSeek-Coder-V2.

    Proprietary (via API): Claude-3-Haiku.

    Task: The models were provided with a JSON-based project context and asked to output a unique, topologically sorted list: ['file1.py', 'file2.py',...] if file2.py depends on file1.py 

| Model Category | Model Name | Format Success | EMR (Logic) | Comment |
| :--- | :--- | :--- | :--- | :--- |
| **Open Source** | Llama 3.2 | 0/100 | 0/100 | Inability to follow strict output constraints. |  
| **Open Source** | DeepSeek-Coder-V2 | 55% | 0/100 | code understanding but not mastering topological logic and formatting. |
| **API**  | Claude-3-Haiku | 100/100 | 0/100 | Understand the prompt but hallucinate |

> **Constat clé :** The models are "guessing" dependencies based on file names rather than verifying actual import relationships within the code
---

## Guide de Reproduction (Google Colab + GPU)

Pour obtenir des performances acceptables (inférence en ~3s au lieu de 100s), utilisez l'environnement GPU de Colab avec Ollama.

### 1. Installation de l'environnement
Dans une cellule Colab :
```python
!pip install colab-xterm -q
%load_ext colabxterm
%xterm

# Dans le terminal
apt-get update && apt-get install zstd -y
curl -fsSL https://ollama.com/install.sh | sh
%apt-get install -y pciutils
