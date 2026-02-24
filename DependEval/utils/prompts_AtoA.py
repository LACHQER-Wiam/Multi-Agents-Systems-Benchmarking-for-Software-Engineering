def build_prompt_AtoA(task):

    # =========================
    # TASK 1
    # =========================
    if task == "task1":

        system_prompt = """
You are an intelligent supervisor orchestrating a multi-agent workflow for a cross-file code modification task.
Do not generate a lot of text
Your ONLY job is to decide which worker should act next:
- code_analyser
- critic
- complete

If you choose 'complete', return STRICTLY the final JSON with this schema:

{
   "called_code_segment": "#file 1 segment being invoked (excluding `import`)",
   "invoking_code_segment": "#file 2 segment invoking #file 1 (excluding `import`)",
   "feature_description": "Description of the new feature",
   "modified_complete_code": "Provide the complete modified code. Use comments like #Modify and #New."
}

Otherwise return routing JSON with the next node.
Return ONLY valid JSON.
"""

        details = {
            "code_analyser": """
Based on the above code snippets, complete the following instructions and output according to the format specified in Step 3:
    Do not generate a lot of text
    1. Identify the segment in one file (#file 1) that is invoked by another file (#file 2) (excluding the import parts).
    2. Modify the given code to implement 
       Modify both #file 1 and #file 2 accordingly.
    3. Ensure the JSON is complete and properly closed.
       Do not truncate.
       If the output is too long, summarize the modified code instead.
    4. Output format:

{
   "called_code_segment": "#file 1 segment being invoked (excluding `import`)",
   "invoking_code_segment": "#file 2 segment invoking #file 1 (excluding `import`)",
   "feature_description": "Description of the new feature",
   "modified_complete_code": "Complete modified code with #Modify and #New comments."
}

Return ONLY valid JSON.
""",

            "critic": """
Criticize the provided answer and argumentation. Do not generate a lot of text
""",

            "finalizer": """
Return ONLY the final JSON:

{
   "called_code_segment": "...",
   "invoking_code_segment": "...",
   "feature_description": "...",
   "modified_complete_code": "..."
}

No markdown.
No explanation.
Only raw JSON.
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
Do not generate a lot of text
keep the full path of the files, including parent folders if mentionned
Workers:
- code_analyser
- critic
- complete

If you choose complete, return ONLY a strict dependency list like:
["parent_file/file1.py", "parent_file/file2.py", "parent_file/file3.py"]

No explanation.
Only the list.
"""

        details = {
            "code_analyser": """
There are files 
Analyze their content and determine the dependency relationship between files.
Do not generate a lot of text
keep the full path of the files, including parent folders if mentionned
Rules:
1. Don't give analysis process.
2. Output ONLY the dependency relationship list.
3. Strict format: ["a.py","b.py","c.py"]
4. At least two filenames.
5. Do not generate code.

""",

            "critic": """
Criticize the provided answer and argumentation. Do not generate a lot of text
keep the full path of the files, including parent folders if mentionned
""",

            "finalizer": """
Return ONLY the final dependency list.
keep the full path of the files, including parent folders if mentionned
Example:
["file1.py", "file2.py", "file3.py"]
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
keep the full path of the files, including parent folders if mentionned
The goal is to have astructure in the format [[file1, file2, file3], [file4, file5], ...], where each sublist represents a chain of dependencies (file2 calls file1, file3 calls file2, etc.).
Workers:
- code_analyser
- critic
- complete

If you choose complete, return ONLY:
[[file1, file2], [file3, file4]]

Coordinate between those workers
"""

        details = {
            "code_analyser": """
You are an AI assistant tasked with generating a project structure based on the given repository information.
keep the full path of the files, including parent folders if mentionned
1. Analyze the project description, function, and file information.
2. Explain the relationships and dependencies between the different files (which file calls which?).
3. Explain your answer
5. Each sublist must contain at least two files.

""",

            "critic": """
Criticize the provided answer and argumentation. 
keep the full path of the files, including parent folders if mentionned
""",

            "finalizer": """
Return ONLY the final structure, based on the discussion between different workers.
keep the full path of the files, including parent folders if mentionned
Example:
[["parent_file/file1.py","parent_file/ile2.py"],["parent_file/file3.py","parent_file/file4.py"]]
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


