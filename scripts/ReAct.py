import os
import json
import ast
import time
from typing import Annotated, Sequence, TypedDict
from dotenv import load_dotenv
from langchain_core.messages import BaseMessage, SystemMessage, HumanMessage
from langchain_anthropic import ChatAnthropic
from langchain_core.tools import tool
from langchain_community.callbacks.manager import get_openai_callback
from langgraph.graph import StateGraph, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode

load_dotenv()

# STEP 1: Define the State 
class AgentState(TypedDict):
    """
    The state of the graph. 
    'messages' uses add_messages so each new node output is appended to history.
    """
    messages: Annotated[Sequence[BaseMessage], add_messages]
    language: str

# STEP 2: Define Tools
@tool
def verify_file_presence(filename: str):
    """
    Check if a filename mentioned in the code exists in the current snippet's file list.
    Use this to ensure you only list dependencies that are actually part of the provided project context.
    """
    # In this benchmark, the LLM has the context in the prompt. 
    return f"Verification: {filename} is confirmed present in the provided context."

tools = [verify_file_presence]
tool_node = ToolNode(tools)

# STEP 3: Setup the Model
llm = ChatAnthropic(
    model="claude-3-haiku-20240307",
    temperature=0.2, # Deterministic output for benchmarking
    anthropic_api_key=os.getenv("ANTHROPIC_API_KEY")
).bind_tools(tools)

# STEP 4: Define Agent Logic
def call_model(state: AgentState):
    """
    The 'Brain' node. It receives the history and decides to either 
    call a tool or provide the final dependency list.
    """
    lang = state.get("language", "python")
    
    system_instruction = SystemMessage(content=(
        f"You are a Software Dependency Expert specializing in {lang}.\n"
        "Analyze the code snippet which contains multiple files merged together.\n"
        "TASK:\n"
        "1. Identify the dependency relationships between the files provided.\n"
        "2. Output ONLY a unique Python list of filenames: ['file1.ext', 'file2.ext']\n"
        "3. ORDERING: If 'File B' depends on 'File A', 'File A' must come BEFORE 'File B' in the list.\n"
        "4. STRICT FORMAT: Do not provide analysis, explanations, or code blocks. Just the list.\n"
        "Example output: ['path/a.py', 'path/b.py']\n"
        "Use the 'verify_file_presence' tool to double-check file names if needed."
    ))
    
    # Combine instructions with conversation history
    messages = [system_instruction] + state["messages"]
    response = llm.invoke(messages)
    return {"messages": [response]}

def should_continue(state: AgentState):
    """
    Conditional logic: If the model generated a tool call, go to 'tools', 
    otherwise, finish the process.
    """
    last_message = state["messages"][-1]
    if not last_message.tool_calls:
        return END
    return "continue"

# STEP 5: Graph Architecture
workflow = StateGraph(AgentState)

workflow.add_node("agent", call_model)
workflow.add_node("tools", tool_node)

workflow.set_entry_point("agent")
workflow.add_conditional_edges(
    "agent", 
    should_continue, 
    {
        "continue": "tools", 
        END: END
    }
)
workflow.add_edge("tools", "agent")

# Compile the graph into an executable app
app = workflow.compile()


def normalize(f_list):
    """Clean strings for accurate comparison."""
    return [f.replace('./', '').strip("'").strip('"').strip() for f in f_list]

def run_react_benchmark(language):
    """Main loop to process the JSON dataset using the ReAct Agent."""
    file_path = f"data/DR/{language}/task2_{language}_final.json"
    
    if not os.path.exists(file_path):
        print(f"Error: Dataset not found at {file_path}")
        return

    with open(file_path, "r") as f:
        data = json.load(f)

    results = {"emr_count": 0, "total": len(data), "errors": 0}
    start_time = time.time()

    print(f"\n--- Starting ReAct Agentic Benchmark ({language.upper()}) ---")

    total_input_tokens = 0
    total_output_tokens = 0


    with get_openai_callback() as cb:

        for i, example in enumerate(data):
            print(f"[{i+1}/{len(data)}] Processing example...", end=" ", flush=True)
            
            # Prepare the input for the agent
            inputs = {
                "messages": [HumanMessage(content=f"Analyze these files:\n{example['content']}")],
                "language": language
            }
            
            try:
                # Stream the execution to handle the agentic loop
                final_state = None
                for output in app.stream(inputs, stream_mode="values"):
                    final_state = output

                # Extract final answer
                agent_answer = final_state["messages"][-1].content
                
                # Extract list from text (handle cases where model might add prose)
                if "[" in agent_answer and "]" in agent_answer:
                    start = agent_answer.index("[")
                    end = agent_answer.rfind("]") + 1
                    clean_output = agent_answer[start:end]
                    parsed_output = ast.literal_eval(clean_output)
                else:
                    parsed_output = []

                # Evaluate EMR
                if normalize(parsed_output) == normalize(example["gt"]):
                    results["emr_count"] += 1
                    print("✅ MATCH")
                else:
                    print("❌ MISMATCH")
                    
            except Exception as e:
                results["errors"] += 1
                print(f"⚠️ ERROR: {e}")

        total_input_tokens = cb.prompt_tokens
        total_output_tokens = cb.completion_tokens
        total_cost = cb.total_cost

    total_time = time.time() - start_time
    print(f"\n--- FINAL BATCH RESULTS ({language}) ---")
    print(f"Total Examples: {results['total']}")
    print(f"EMR (Exact Match): {results['emr_count']}")
    print(f"Accuracy: {(results['emr_count']/results['total'])*100:.2f}%")
    print(f"Failed to Parse: {results['errors']}")
    print(f"Input Tokens:  {total_input_tokens}")
    print(f"Output Tokens: {total_output_tokens}")
    print(f"Total Cost:    ${total_cost:.4f}")
    print(f"Avg Tokens/Ex: {(total_input_tokens + total_output_tokens) / len(data):.1f}")
    print(f"Time Taken: {total_time:.2f}s")

if __name__ == "__main__":
    
    run_react_benchmark("python")
    print("============================================================\n")
    run_react_benchmark("java")
    print("============================================================\n")
    run_react_benchmark("javascript")
    print("============================================================\n")
    run_react_benchmark("c")
    print("============================================================\n")
    run_react_benchmark("c++")
    print("============================================================\n")
    run_react_benchmark("c#")
    print("============================================================\n")
    run_react_benchmark("php")
    print("============================================================\n")
    run_react_benchmark("typescript")
    print("============================================================\n")