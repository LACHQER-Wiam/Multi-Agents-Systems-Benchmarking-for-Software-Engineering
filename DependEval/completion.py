# Task num2 : Depedency Recognition
import ast
import os
import json 
import time
from dotenv import load_dotenv
from langchain_ollama import ChatOllama
from langchain_core.prompts import ChatPromptTemplate
from langchain_anthropic import ChatAnthropic

extensions = {'python': '.py', 'java': '.java', 'javascript': '.js', 'c': '.c', 'c++': '.cpp', 'c#': '.cs', 'php': '.php', 'typescript': '.ts'}

# Upload the .env (default) file variable to the environment
load_dotenv()

# THE API_KEY:
api_key = os.getenv("ANTHROPIC_API_KEY")

# Initialize the ChatAnthropic model
llm = ChatAnthropic(
    model="claude-opus-4-6",
    # temperature=0.2, # from the paper
    # model_kwargs = {
    #     "top_p": 0.95 # Filtre la liste des mots possibles.
    # },
    anthropic_api_key=api_key
)

def normalize(f_list):
    return [f.replace('./', '').strip() for f in f_list]

def run_benchmark(language):
    try:
        with open(f"data/DR/{language}/task2_{language}_final.json","r") as f:
            data = json.load(f)

        results = {"emr_count":0, "format_fails":0, "logic_fails":0}
        
        start_time = time.time() 
        for i in range(len(data)):
            example = data[i]
            print(f"We are testing example {i+1} / {len(data)}")
            ground_truth = example["gt"]
            code_content = example["content"]

            # RUN THE MODEL INFERENCE a structured way to build a chat conversation
            prompt = ChatPromptTemplate.from_messages([
            ("system", f"There are files #filename. Analyze their content and determine the dependency relationship between files. Output with the following request. 1.Don’t give analysis process and using the same file title. 2.Simply and only output the dependency relationship list using its file names with the format output a unique list [’a.{extensions[language]}’,’b.{extensions[language]}’,’c.{extensions[language]}’] if b depends on a , c depends on b. 3.You must strictly output the response with the format:[’a.{extensions[language]}’,’b.{extensions[language]}’,’c.{extensions[language]}’] Example output:['file1.{extensions[language]}', 'file2.{extensions[language]}', 'file3.{extensions[language]}'] Here’s the code snippet: #code_content."),
            ("user", "{code}")   
            ])
            # Chat models are trained with roles (system, user, assistant) {"role": "system", "content": system_message},
            #       
            #                                                         {"role": "user", "content": "code_content:\n<actual code>"}
            
            chain = prompt | llm  # This is the pipeline : the output of the prompt is the input of the llm
            response = chain.invoke({'code': code_content}) # This runs the inference
            model_output = response.content.strip() # Get the content of the response
            #print(f"Model output: {model_output}")

            try:
            # Try to parse the output as a list
                clean_output = model_output.replace("```python", "").replace("```", "").replace(f"```{language}", "").strip()

                # "Here is the answer : ['a.php', 'b.php']" -> "['a.php', 'b.php']"
                if "[" in clean_output and "]" in clean_output:
                    start = clean_output.index("[")
                    end = clean_output.index("]") + 1
                    clean_output = clean_output[start:end]
                parsed_output = ast.literal_eval(clean_output)    

                if not isinstance(parsed_output, list) or any(isinstance(i, list) for i in parsed_output):
                    results["format_fails"] += 1
                    continue
                    
                # 2. Check Logic (Is the order correct?)
                if normalize(parsed_output) == normalize(ground_truth):
                    results["emr_count"] += 1
                else:
                    results["logic_fails"] += 1
                    
            except:
                results["format_fails"] += 1
        
        end_time = time.time()

        # RESULTS:
        print(f"\n BATCH RESULTS of {language}:")
        print(f"the batch size : {len(data)}")
        print(f"EMR batch: {results['emr_count']} / {len(data)}")
        print(f"Format Error: {results['format_fails']} / {len(data)}")
        print(f"Logic Error: {results['logic_fails']} / {len(data)}")
        print(f"Total time: {end_time - start_time:.2f} seconds")
        print(f"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^")

    except FileNotFoundError:
        print(f"The file data/DR/{language}/task2_{language}_final.json was not found.")
    except Exception as e:
        print(f"Error reading the file: {e}")

if __name__ == "__main__":
    run_benchmark("python")
    run_benchmark("java")
    run_benchmark("javascript")
    run_benchmark("c")
    run_benchmark("c++")
    run_benchmark("c#")
    run_benchmark("php")
    run_benchmark("typescript")