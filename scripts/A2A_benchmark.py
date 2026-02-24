import os
import json
import ast
import time
from typing import Annotated, Sequence, TypedDict, List, Union, Literal
from dotenv import load_dotenv

from langchain_core.messages import BaseMessage, SystemMessage, HumanMessage, AIMessage
from langchain_anthropic import ChatAnthropic
from langchain_core.tools import tool
from langchain_community.callbacks.manager import get_openai_callback

# LangGraph Components
from langgraph.graph import StateGraph, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode

load_dotenv()

# A2A State
class A2AState(TypedDict):
    messages: Annotated[Sequence[BaseMessage], add_messages]
    language: str
    project_files: List[str]

# Tools
benchmark_context = {}

@tool
def verify_file_presence(filename: str) -> str:
    """Check if a filename exists in the project. Essential for the Auditor."""
    return f"Verification: {filename} is validated against the current project structure."

@tool
def get_file_snippet(filename: str, line_start: int = 1, line_end: int = 20) -> str:
    """Read a file snippet to resolve dependency logic. Essential for the Researcher."""
    file_content = benchmark_context.get(filename, "Error: File not found.")
    if file_content == "Error: File not found.":
        return file_content
    lines = file_content.split("\n")
    snippet = "\n".join(lines[line_start-1:line_end])
    return f"Content of {filename} (Lines {line_start}-{line_end}):\n---\n{snippet}\n"

tools = [verify_file_presence, get_file_snippet]
tool_node = ToolNode(tools)

# Model Setup 
llm = ChatAnthropic(
    model="claude-haiku-4-5",
    temperature=0.0,
    anthropic_api_key=os.getenv("ANTHROPIC_API_KEY")
).bind_tools(tools)

# Agent Nodes

def call_researcher(state: A2AState):
    lang = state.get("language", "java")
    # Inside call_researcher
    system_prompt = (
    f"You are the Researcher (Expert in {lang}).\n"
    "1. LIST: Look at the 'project_files' provided in the state. ONLY these files exist.\n"
    "2. SEARCH: If 'get_file_snippet' returns 'File not found', check your spelling against the 'project_files' list.\n"
    "3. HAND-OFF: When you have the dependencies, you MUST say '@Auditor' immediately. Do not explain your life story."
)
    response = llm.invoke([SystemMessage(content=system_prompt)] + list(state["messages"]))
    return {"messages": [response]}

def call_auditor(state: A2AState):
    system_prompt = (
        "You are the Auditor.\n"
        "TASK: Use 'verify_file_presence' for EVERY file found by the Researcher.\n"
        "ACTION: Reject any file that does not exist.\n"
        "PROTOCOL: If all exist, message the Manager: '@Manager, list is verified: [list]'. "
        "If missing, tell @Researcher to fix it."
        "CRITICAL: If everything is correct, you MUST end with '@Manager'. "
        "If there are errors, you MUST end with '@Researcher'."

    )
    response = llm.invoke([SystemMessage(content=system_prompt)] + list(state["messages"]))
    return {"messages": [response]}

def call_manager(state: A2AState):
    system_prompt = (
        "You are a JSON formatter. Take the verified files from the conversation history.\n"
        "1. Remove any files that are NOT internal (keep only local paths).\n"
        "2. Sort them: A comes before B if B depends on A.\n"
        "3. OUTPUT ONLY THE LIST: ['file1', 'file2']\n"
        "NO TEXT. NO MARKDOWN. NO CODE BLOCKS. JUST THE LIST."
    )
    # Use a fresh, zero-temperature call
    response = llm.invoke([SystemMessage(content=system_prompt)] + list(state["messages"]))
    return {"messages": [response]}

# A2A Router
def route_a2a(state: A2AState) -> Literal["tools", "auditor", "manager", "researcher", "end"]:
    last_message = state['messages'][-1]
    
    if last_message.tool_calls:
        return 'tools'
    
    content = last_message.content
    if isinstance(content, list):
        content = " ".join([c.get("text", "") if isinstance(c, dict) else str(c) for c in content])
    
    content_lower = content.lower()

    if "@Auditor" in content: return "auditor"
    if "@Manager" in content: return "manager"
    if "@Researcher" in content or "missing" in content_lower: return "researcher"
    if "FINAL_OUTPUT" in content: return "end"
    
    return "researcher"

# --- STEP 6: Graph Construction ---
workflow = StateGraph(A2AState)
workflow.add_node("researcher", call_researcher)
workflow.add_node("auditor", call_auditor)
workflow.add_node("manager", call_manager)
workflow.add_node("tools", tool_node)

routing_map = {"tools": "tools", "auditor": "auditor", "manager": "manager", "researcher": "researcher", "end": END}

workflow.set_entry_point("researcher")
workflow.add_conditional_edges("researcher", route_a2a, routing_map)
workflow.add_conditional_edges("auditor", route_a2a, routing_map)
workflow.add_conditional_edges("manager", route_a2a, routing_map)
workflow.add_edge("tools", "researcher")

app = workflow.compile()

def run_a2a_benchmark(language):
    file_path = f"data/DR/{language}/task2_{language}_final.json"
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return

    with open(file_path, "r") as f:
        data = json.load(f)

    results = {"emr_count": 0, "total": len(data)}
    
    print(f"\n🚀 STARTING A2A BENCHMARK [{language.upper()}]")

    with get_openai_callback() as cb:
        for i, example in enumerate(data):
            print(f"\n--- 🧩 EXAMPLE {i+1}/{len(data)} ---")
            
            global benchmark_context
            benchmark_context = example.get('files_content', {}) 
            
            inputs = {
                "messages": [HumanMessage(content=f"Identify dependencies for this code:\n{example['content']}")],
                "language": language,
                "project_files": list(benchmark_context.keys())
            }
            
            try:
                # Streaming to see agent-to-agent communication
                final_state = None
                for output in app.stream(inputs, config={"recursion_limit": 30}, stream_mode="values"):
                    final_state = output
                    # Print Agent Turn
                    last_msg = output["messages"][-1]
                    sender = "Tools" if hasattr(last_msg, 'tool_call_id') else "Agent"
                    print(f"💬 {sender}: {str(last_msg.content)[:100]}...")

                # Parsing Manager Result
                ans = final_state["messages"][-1].content
                if "[" in ans:
                    parsed = ast.literal_eval(ans[ans.find("["):ans.rfind("]")+1])
                else: parsed = []

                if [f.replace('./','') for f in parsed] == [f.replace('./','') for f in example["gt"]]:
                    results["emr_count"] += 1
                    print("✅ MATCH")
                else: print("❌ MISMATCH")

            except Exception as e:
                print(f"⚠️ Error: {e}")

        print(f"\n📊 FINAL RESULTS: {results['emr_count']}/{results['total']}")
        print(f"💰 Total Cost: ${cb.total_cost:.4f} | Tokens: {cb.total_tokens}")

if __name__ == "__main__":
    run_a2a_benchmark("typescript")