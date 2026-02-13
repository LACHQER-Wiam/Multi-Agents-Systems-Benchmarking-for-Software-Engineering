# Task num2 : Depedency Recognition using Llama3.2
import ast
import json 
import time
from langchain_ollama import ChatOllama
from langchain_core.prompts import ChatPromptTemplate

# Initialize the Ollama model
llm = ChatOllama(
    model="llama3.2",
    temperature=0, # non creative task 
    api_base = "http://localhost:11434"
)

def run_benchmark(batch_size=10):
    try:
        with open("data/python/task2_python_final.json","r") as f:
            data = json.load(f)

        results = {"emr_count":0, "format_fails":0, "logic_fails":0}
        
        start_time = time.time() 
        for i in range(batch_size):
            example = data[i]
            print(f"We are testing example {i+1} / {batch_size}")
            ground_truth = example["gt"]
            code_content = example["content"]

            # RUN THE MODEL INFERENCE a structured way to build a chat conversation
            prompt = ChatPromptTemplate.from_messages([
            ("system", "There are files #filename. Analyze their content and determine the dependency relationship between files. Output with the following request. 1.Don’t give analysis process and using the same file title. 2.Simply and only output the dependency relationship list using its file names with the format [’a.py’,’b.py’,’c.py’] if b depends on a , c depends on b. 3.You must strictly output the response with the format:[’a.py’,’b.py’,’c.py’] Example output:['file1.py', 'file2.py', 'file3.py'] Here’s the code snippet: #code_content."),
            ("user", "{code}")   
            ])
            # Chat models are trained with roles (system, user, assistant) {"role": "system", "content": system_message},
            #       
            #                                                         {"role": "user", "content": "code_content:\n<actual code>"}
            
            chain = prompt | llm  # This is the pipeline : the output of the prompt is fed into the llm
            response = chain.invoke({'code': code_content}) # This runs the inference
            model_output = response.content.strip() # Get the content of the response

            try:
            # Try to parse the output as a list
                clean_output = model_output.replace("```python", "").replace("```", "").strip()
                parsed_output = ast.literal_eval(clean_output)    

                if not isinstance(parsed_output, list) or any(isinstance(i, list) for i in parsed_output):
                    results["format_fails"] += 1
                    continue
                    
                # 2. Check Logic (Is the order correct?)
                if parsed_output == ground_truth:
                    results["emr_count"] += 1
                else:
                    results["logic_fails"] += 1
                    
            except:
                results["format_fails"] += 1
        
        end_time = time.time()

        # RESULTS:
        print("\n BATCH RESULTS  :")
        print(f"the batch size : {batch_size}")
        print(f"EMR batch: {results['emr_count']} / {batch_size}")
        print(f"Format Error: {results['format_fails']} / {batch_size}")
        print(f"Logic Error: {results['logic_fails']} / {batch_size}")
        print(f"Total time: {end_time - start_time:.2f} seconds")
        

    except FileNotFoundError:
        print("The file data/python/task2_python.json was not found.")
    except Exception as e:
        print(f"Error reading the file: {e}")

if __name__ == "__main__":
    run_benchmark()
    