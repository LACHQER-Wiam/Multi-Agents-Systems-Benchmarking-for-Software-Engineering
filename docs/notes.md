# Multi-Agents Systems Benchmarking for Software Engineering

Ce projet vise à évaluer les performances des systèmes multi-agents et des modèles LLM open-source sur des tâches complexes d'ingénierie logicielle, notamment la reconnaissance de dépendances (Dependency Recognition).

## État Actuel des Recherches (Task 2)

Nous avons établi un baseline en testant des modèles locaux sur la **Task 2 (Dependency Recognition)** du benchmark DependEval.

| Modèle | Format Success | EMR (Exact Match) | Note |
| :--- | :--- | :--- | :--- |
| **Llama 3.2 (3B)** | 0% | 0/100 | Difficulté à suivre le format de liste pure. |
| **DeepSeek-Coder-V2** | 55% | 0/100 | Bon respect du format, mais erreurs de logique topologique. |

> **Constat clé :** L'échec systématique de l'Exact Match Rate (EMR) sur les modèles individuels souligne la nécessité d'une approche **Multi-Agents** pour valider et corriger la logique de dépendance.

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
