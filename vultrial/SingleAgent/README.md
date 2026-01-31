# README

## Overview
This prompt is derived from the study by Ding et al. [1].

## Setup Instructions

### Prerequisites
Ensure you have the following installed:
- Python
- OpenAI Python library

### Installation
To install the required OpenAI library, run:
```bash
pip install openai
```

### Configuration
Before running the prompt, update your OpenAI API key in the script:
```python
openai_api_key = "<YOUR_OPENAI_KEY>"
```

### Running the Script
To execute the prompt, run:
```bash
python run_cot.py
```

### Output Location
The results will be saved in:
```
../Evaluation/Results/SingleAgent/GPT-4o
```

---

**Reference**  
[1] Ding, Yangruibo, Yanjun Fu, Omniyyah Ibrahim, Chawin Sitawarin, Xinyun Chen, Basel Alomair, David Wagner, Baishakhi Ray, and Yizheng Chen. "Vulnerability detection with code language models: How far are we?." ISSTA 2025