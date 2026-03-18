def build_prompt_AtoA(task):

    # =========================
    # TASK 1
    # =========================
    if task == "task1":

        system_prompt = """
You are an intelligent supervisor orchestrating a multi-agent workflow for a cross-file code modification task.
Do not generate a lot of text.

CRITICAL: You MUST respond with ONLY valid JSON. No explanations, no markdown, no text before or after.

Your ONLY job is to decide which worker should act next: code_analyser, critic, or complete.

RESPONSE FORMAT - You must choose ONE of these:

1. If routing to code_analyser:
{"messages": [{"role": "assistant", "content": "Analyzing code..."}], "next": "code_analyser"}

2. If routing to critic:
{"messages": [{"role": "assistant", "content": "Reviewing analysis..."}], "next": "critic"}

3. If choosing complete:
{"messages": [{"role": "assistant", "content": "Complete"}], "next": "complete"}

Output ONLY the JSON object. No markdown backticks. No explanations.
"""

        details = {
            "code_analyser": """
CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Based on the above code snippets:
1. Identify the segment in file #file 1 that is invoked by file #file 2 (excluding imports).
2. Modify both files to implement the requested feature.
3. Ensure complete, properly closed JSON output.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:
{"messages": [{"role": "assistant", "content": "Analysis: [your analysis here]"}], "next": "critic"}

Do NOT include markdown backticks or any text outside the JSON.
""",

            "critic": """
CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Criticize the provided analysis and code modifications. Suggest improvements.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:
{"messages": [{"role": "assistant", "content": "Critique: [your critique here]"}], "next": "supervisor"}

Do NOT include markdown backticks or any text outside the JSON.
""",

            "finalizer": """
CRITICAL: You MUST respond with ONLY valid JSON object. Absolutely no markdown, no explanations, no text outside JSON.

Return the final output with these exact fields:

{"called_code_segment": "...", "invoking_code_segment": "...", "feature_description": "...", "modified_complete_code": "..."}

Nothing else. Only JSON.
"""
        }

        description = {
            "supervisor": "Supervises multi-file feature implementation.",
            "code_analyser": "Identifies and modifies cross-file code segments.",
            "critic": "criticise the code_analyser answers and challenges it",
            "finalizer": "Returns final structured JSON output.",
            "global_agent": "Performs structured cross-file feature modification."
        }

    # =========================
    # TASK 2
    # =========================
    elif task == "task2":

        system_prompt = """
You are an intelligent supervisor orchestrating a dependency analysis task.
Do not generate a lot of text.
Keep the full path of the files, including parent folders if mentioned.

CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Your job: Decide which worker should act next: code_analyser, critic, or complete.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:

If routing to code_analyser:
{"messages": [{"role": "assistant", "content": "Analyzing dependencies..."}], "next": "code_analyser"}

If routing to critic:
{"messages": [{"role": "assistant", "content": "Reviewing..."}], "next": "critic"}

If routing to complete:
{"messages": [{"role": "assistant", "content": "Complete"}], "next": "complete"}

Output ONLY JSON. No markdown backticks. No other text.
"""

        details = {
            "code_analyser": """
CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Analyze the file content and determine dependency relationships.
Keep full file paths including parent folders.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:
{"messages": [{"role": "assistant", "content": "["file1.py", "file2.py", "file3.py"]"}], "next": "critic"}

Rules:
1. Output ONLY the dependency list in JSON format
2. Keep full paths
3. At least two files
4. No analysis text outside the JSON

Do NOT include markdown backticks.
""",

            "critic": """
CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Criticize the provided dependency analysis and suggest corrections if needed.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:
{"messages": [{"role": "assistant", "content": "Critique: [your critique]"}], "next": "supervisor"}

Do NOT include markdown backticks.
""",

            "finalizer": """
CRITICAL: You MUST respond with ONLY valid JSON. Absolutely no markdown, no text outside JSON.

Return ONLY the final dependency list as a JSON array:

["file1.py", "file2.py", "file3.py"]

Nothing else. Only the list in JSON format.
"""
        }

        description = {
            "supervisor": "Supervises dependency detection workflow.",
            "code_analyser": "Determines inter-file dependencies.",
            "critic": "criticise the code_analyser answers and challenges it",
            "finalizer": "Returns final dependency list.",
            "global_agent": "Analyzes file dependencies."
        }

    # =========================
    # TASK 4
    # =========================
    elif task == "task4":

        system_prompt = """
You are an intelligent supervisor orchestrating project structure generation.
Keep full file paths, including parent folders if mentioned.

CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Goal: Generate structure [[file1, file2, file3], [file4, file5], ...] where each sublist is a dependency chain.

Your job: Decide which worker should act next: code_analyser, critic, or complete.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:

If routing:
{"messages": [{"role": "assistant", "content": "Routing..."}], "next": "code_analyser"}

If complete:
{"messages": [{"role": "assistant", "content": "Complete"}], "next": "complete"}

Output ONLY JSON. No markdown. No other text.
"""

        details = {
            "code_analyser": """
CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Analyze the repository and generate dependency chains.
Keep full file paths with parent folders.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:
{"messages": [{"role": "assistant", "content": "[["parent/file1.py", "parent/file2.py"], ["parent/file3.py", "parent/file4.py"]]"}], "next": "critic"}

Rules:
1. Output ONLY the structure in JSON format
2. Each sublist: minimum 2 files
3. Keep full paths
4. Explain relationships briefly

Do NOT include markdown backticks.
""",

            "critic": """
CRITICAL: You MUST respond with ONLY valid JSON. No text, no markdown, no explanations.

Criticize the dependency chain structure and suggest improvements if needed.

RESPONSE FORMAT - MUST BE VALID JSON ONLY:
{"messages": [{"role": "assistant", "content": "Critique: [your critique]"}], "next": "supervisor"}

Do NOT include markdown backticks.
""",

            "finalizer": """
CRITICAL: You MUST respond with ONLY valid JSON. Absolutely no markdown, no text outside JSON.

Return ONLY the final structure as JSON array of arrays:

[["parent/file1.py","parent/file2.py"],["parent/file3.py","parent/file4.py"]]

Nothing else. Only the structure.
"""
        }

        description = {
            "supervisor": "Supervises project dependency structure generation.",
            "code_analyser": "Generates dependency chains.",
            "critic": "criticise the code_analyser answers and challenges it",
            "finalizer": "Returns final dependency chains.",
            "global_agent": "Builds structured repository dependency chains."
        }

    else:
        raise ValueError(f"Unsupported task: {task}")

    return system_prompt, details, description


