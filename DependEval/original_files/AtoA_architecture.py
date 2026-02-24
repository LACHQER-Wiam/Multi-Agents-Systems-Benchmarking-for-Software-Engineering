import warnings
warnings.filterwarnings("ignore")

from langgraph.graph import StateGraph, START, END
from langchain_core.output_parsers import PydanticOutputParser
from pydantic import BaseModel, Field
from typing import Dict, Optional, List, TypedDict
from langgraph.checkpoint.memory import MemorySaver
import anthropic
import os
import json
import asyncio
import inspect
import traceback
import uvicorn
import argparse
# ---------------------------
# 1) A2A ADK imports
# ---------------------------
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import Task, TaskState, TaskStatus, TextPart
from a2a.utils import new_agent_text_message, new_task

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore 
from a2a.server.apps import A2AStarletteApplication 
from a2a.types import AgentCard, AgentCapabilities, AgentSkill


from ..utils.prompts_AtoA import build_prompt_AtoA
# =========================
# Constantes
# =========================

parser = argparse.ArgumentParser()

parser.add_argument("--task", required=True)
parser.add_argument("--language", required=True)
parser.add_argument("--model_name", type=str, default='claude-haiku-4-5')

parser.add_argument("--temperature", type=float, default=0.0)
parser.add_argument("--max_token_nums", type=int, default=1000)
parser.add_argument("--max_rounds", type=int, default=3)

args = parser.parse_args()

model_name = args.model_name
temperature = args.temperature
max_tokens = args.max_token_nums
max_rounds = args.max_rounds

task = args.task
language = args.language

# =========================
# PROMPTS
# =========================

system_prompt,  details, description = build_prompt_AtoA(task)

# =========================
# STATE
# =========================

class State(TypedDict):
    messages: List[Dict]
    analysis: Optional[str]
    critique: Optional[str]
    next: Optional[str]
    rounds: int

# =========================
# CLAUDE WRAPPER
# =========================

class ClaudeLLM:

    def __init__(self, model_name="claude-haiku-4-5", temperature=0, max_tokens=8000):
        self.client = anthropic.Client(
            api_key=os.environ.get("ANTHROPIC_API_KEY"),
            timeout=10000)
        self.model_name = model_name
        self.temperature = temperature
        self.max_tokens = max_tokens

    
    def _prepare_messages(self, messages):
        system_prompt = None
        filtered_messages = []

        for i, msg in enumerate(messages):
            if not isinstance(msg, dict):
                continue

            role = (msg.get("role") or "").lower()
            content = msg.get("content", "")

            if role == "system":
                system_prompt = content.strip()
                continue

            # Anthropic accepte seulement user / assistant
            if role not in {"user", "assistant"}:
                role = "assistant"

            # TRIM TRAILING WHITESPACE
            content = content.rstrip()

            filtered_messages.append({
                "role": role,
                "content": content
            })

        return system_prompt, filtered_messages

    def invoke(self, messages):
        system_prompt, filtered_messages = self._prepare_messages(messages)

        try:
            response = self.client.messages.create(
                model=self.model_name,
                max_tokens=self.max_tokens,
                temperature=self.temperature,
                system=system_prompt,
                messages=filtered_messages,
                stream=True,
            )

            if response.content:
                for block in response.content:
                    if block.type == "text" and block.text:
                        return block.text

            # pas de raise
            return '{"messages":[{"role":"assistant","content":"LLM returned empty output."}],"next":"complete"}'
        except Exception as e:
            return f'{{"messages":[{{"role":"assistant","content":"LLM error: {type(e).__name__}: {str(e)}"}}],"next":"complete"}}'

llm = ClaudeLLM(model_name=model_name, temperature=temperature, max_tokens=max_tokens)



# =========================
# PYDANTIC MODELS
# =========================

class Router(BaseModel):
    messages: list = Field(description="list of assistant messages")
    next: str = Field(description="next node")

class FinalOutput(BaseModel):
    correct_version: str
    justification: str

# =========================
# ROUTING FUNCTION
# =========================

def routing(state: State):
    """Route to the next valid node, with fallback to supervisor if invalid."""
    next_node = state.get("next", "supervisor")

    # Valid nodes
    valid_nodes = ["code_analyser", "critic", "complete", "end", "supervisor"]

    # Normalize and validate
    next_node_lower = str(next_node).lower().strip()

    if next_node_lower in valid_nodes:
        return next_node_lower

    # Fallback to supervisor for invalid routes
    print(f"⚠️  Invalid route '{next_node}', falling back to supervisor")
    return "supervisor"

# =========================
# NODES
# =========================
def supervisor_node(state: State):

    # Stop condition - max 3 rounds
    if state.get("rounds", 0) >= max_rounds:
        return {
            "next": "complete",
            "rounds": state.get("rounds", 0) + 1,
            "messages": state["messages"],
            "analysis": state.get("analysis"),
            "critique": state.get("critique"),
        }

    parser = PydanticOutputParser(pydantic_object=Router)

    messages = [
        {
            "role": "system",
            "content": system_prompt + "\n" + parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages)

    # Nettoyage markdown éventuel
    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    print(f"📝 Supervisor raw response: {response_text[:200]}")
    print(f"📝 Supervisor cleaned: {cleaned[:200]}")

    try:
        parsed = parser.parse(cleaned)
        print(f"✅ Parsed successfully: next={parsed.next}, messages={len(parsed.messages)}")

        # On ajoute SEULEMENT le message conversationnel utile
        if parsed.messages and len(parsed.messages) > 0 and isinstance(parsed.messages[0], dict):
            assistant_message = parsed.messages[0].get("content", cleaned)
        else:
            assistant_message = cleaned

        # Ensure next is valid
        next_value = str(parsed.next).lower().strip() if parsed.next else "supervisor"
        print(f"🎯 Next value: '{next_value}'")

        return {
            "messages": state["messages"] + [
                {"role": "assistant", "content": assistant_message}
            ],
            "next": next_value,
            "rounds": state.get("rounds", 0) + 1,
            "analysis": state.get("analysis"),
            "critique": state.get("critique"),
        }

    except Exception as e:
        # Fallback sécurisé
        print(f"❌ Parsing error in supervisor: {e}")
        print(f"❌ Trying to parse as JSON manually...")

        # Try to extract next value from JSON manually
        try:
            json_obj = json.loads(cleaned)
            next_value = str(json_obj.get("next", "supervisor")).lower().strip()
            print(f"🎯 Manual extraction next: '{next_value}'")
        except:
            next_value = "supervisor"
            print(f"🎯 Fallback next: '{next_value}'")

        return {
            "messages": state["messages"] + [
                {"role": "assistant", "content": cleaned}
            ],
            "next": next_value,
            "rounds": state.get("rounds", 0) + 1,
            "analysis": state.get("analysis"),
            "critique": state.get("critique"),
        }

def code_analyser_node(state: State):

    parser = PydanticOutputParser(pydantic_object=Router)

    messages = [
        {
            "role": "system",
            "content": details["code_analyser"] + "\n" + parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages)

    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    try:
        parsed = parser.parse(cleaned)

        if parsed.messages and len(parsed.messages) > 0 and isinstance(parsed.messages[0], dict):
            assistant_message = parsed.messages[0].get("content", cleaned)
        else:
            assistant_message = cleaned

        # Ensure next is valid
        next_value = str(parsed.next).lower().strip() if parsed.next else "supervisor"

        return {
            "messages": state["messages"] + [
                {"role": "assistant", "content": assistant_message}
            ],
            "analysis": cleaned,
            "next": next_value,
            "critique": state.get("critique"),
        }

    except Exception as e:
        print(f"❌ Parsing error in code_analyser: {e}")
        return {
            "messages": state["messages"] + [
                {"role": "assistant", "content": cleaned}
            ],
            "analysis": cleaned,
            "next": "supervisor",
            "critique": state.get("critique"),
        }
    
def critic_node(state: State):

    parser = PydanticOutputParser(pydantic_object=Router)

    messages = [
        {
            "role": "system",
            "content": details["critic"] + "\n" + parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages)

    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    try:
        parsed = parser.parse(cleaned)

        if parsed.messages and len(parsed.messages) > 0 and isinstance(parsed.messages[0], dict):
            assistant_message = parsed.messages[0].get("content", cleaned)
        else:
            assistant_message = cleaned

        # Ensure next is valid
        next_value = str(parsed.next).lower().strip() if parsed.next else "supervisor"

        return {
            "messages": state["messages"] + [
                {"role": "assistant", "content": assistant_message}
            ],
            "critique": cleaned,
            "next": next_value,
            "analysis": state.get("analysis"),
        }

    except Exception as e:
        print(f"❌ Parsing error in critic: {e}")
        return {
            "messages": state["messages"] + [
                {"role": "assistant", "content": cleaned}
            ],
            "critique": cleaned,
            "next": "supervisor",
            "analysis": state.get("analysis"),
        }
    
def finalizer_node(state: State):

    final_prompt = details["finalizer"]

    messages = [
        {
            "role": "system",
            "content": final_prompt,
        }
    ] + state["messages"]

    response_text = llm.invoke(messages)

    # Nettoyage minimal markdown éventuel
    cleaned = (
        response_text
        .replace("```json", "")
        .replace("```", "")
        .strip()
    )

    return {
        "messages": [
            {
                "role": "assistant",
                "content": cleaned,
            }
        ],
        "next": "end",
        "analysis": state.get("analysis"),
        "critique": state.get("critique"),
    }
# =========================
# BUILD GRAPH
# =========================
def route_from_supervisor(state: State) -> str:
    n = (state.get("next") or "").strip().lower()
    if n in {"end", "finish", "done"}:
        return "complete"
    if n not in {"code_analyser", "critic", "complete"}:
        return "complete"
    return n

def route_from_code_analyser(state: State) -> str:
    n = (state.get("next") or "").strip().lower()
    if n in {"end", "finish", "done"}:
        return "complete"
    # code_analyser ne doit pas router vers code_analyser
    if n not in {"critic", "supervisor", "complete"}:
        return "supervisor"
    return n

def route_from_critic(state: State) -> str:
    n = (state.get("next") or "").strip().lower()
    if n in {"end", "finish", "done"}:
        return "complete"
    # critic ne doit pas router vers code_analyser
    if n not in {"supervisor", "complete"}:
        return "supervisor"
    return n

memory = MemorySaver()
builder = StateGraph(State)

builder.add_node("supervisor", supervisor_node)
builder.add_node("code_analyser", code_analyser_node)
builder.add_node("critic", critic_node)
builder.add_node("finalizer", finalizer_node)
builder.add_edge("finalizer", END)

builder.add_edge(START, "supervisor")

builder.add_conditional_edges(
    "supervisor",
    route_from_supervisor,
    {
        "code_analyser": "code_analyser",
        "critic": "critic",
        "complete": "finalizer",
    }
)

builder.add_conditional_edges(
    "code_analyser",
    route_from_code_analyser,
    {
        "supervisor": "supervisor",
        "critic": "critic",
        "complete": "finalizer",
    }
)

builder.add_conditional_edges(
    "critic",
    route_from_critic,
    {
        "supervisor": "supervisor",
        "code_analyser": "code_analyser",
        "complete": "finalizer",
    }
)

graph = builder.compile(checkpointer=memory)

# =========================
# RUN
# =========================

config = {
    "configurable": {
        "thread_id": "test-thread"
    }
}

initial_state = {
    "messages": [
        {
            "role": "user",
            "content": """Please analyze this Python function and review its correctness:

```python
def add(a, b):
    return a - b
```"""
        }
    ],
    "analysis": None,
    "critique": None,
    "next": None,
    "rounds": 0
}



# ---------------------------
# 2) Import your LangGraph graph + agent_card
# ---------------------------
# IMPORTANT: graph must be compiled already, e.g. graph = builder.compile(...)
# from supervisor import graph
# from agent_card import agent_card


# ---------------------------
# Supervisor Skill
# ---------------------------

skill_supervisor = AgentSkill(
    id='supervisor',
    name='Supervisor Orchestrator',
    description=(description["supervisor"]), 
    tags=['orchestration', 'routing', 'multi-agent']
)

# ---------------------------
# Code Analyzer Skill
# ---------------------------

skill_code_analyser = AgentSkill(
    id='code-analyser',
    name='Code Analyzer',
    description=(description["code_analyser"]),
    tags=['code-analysis', 'python', 'bug-detection']
)

# ---------------------------
#  Critic Skill
# ---------------------------

skill_critic = AgentSkill(
    id='critic',
    name='Code Critic',
    description=(description["critic"]),
    tags=['code-review', 'critique', 'validation']
)

# ---------------------------
#  Finalizer Skill
# ---------------------------

finalizer_skill = AgentSkill(
    id='finalizer',
    name='Finalizer',
    description=(description["finalizer"]),
    OutputModes=["application/json"],
    tags=['finalization', 'output-generation']
)

# ---------------------------
#  Agent Card
# ---------------------------

agent_card = AgentCard(
    name='Multi-Agent Code Review Agent',
    description=description["global_agent"],
    url='http://localhost:10008/',
    version='1.0.0',
    defaultInputModes=['text'],
    defaultOutputModes=['text'],
    capabilities=AgentCapabilities(
        streaming=True  # Changed: using ainvoke() instead of astream()
    ),
    authentication={
        "schemes": ["basic"]
    },
    skills=[skill_code_analyser, skill_critic, skill_supervisor, finalizer_skill])

# For this snippet, we assume these are available:
# graph is already compiled from line 311
# agent_card is already defined from line 428


# ---------------------------
# 4) The A2A Executor wrapping LangGraph
# ---------------------------
class LanggraphAgentExecutor(AgentExecutor):
    def __init__(self):
        self.agent = graph

    async def _maybe_await(self, x):
        """Await x if it's awaitable, else return it."""
        if inspect.isawaitable(x):
            return await x
        return x

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        try:
            query = context.get_user_input()

            task = context.current_task
            if not task:
                task = new_task(context.message)
                # ✅ IMPORTANT: publish task creation event immediately
                await self._maybe_await(event_queue.enqueue_event(task))
            
            print(f"TAAAASK: {task}")

            updater = TaskUpdater(event_queue, task.id, task.context_id)

            input_data = {
                "messages": [{"role": "user", "content": query}],
                "analysis": None,
                "critique": None,
                "next": None,
                "rounds": 0,
            }
            config = {"configurable": {"thread_id": task.context_id}}

            try:
                # Run graph to completion
                result = await self.agent.astream(input_data, config=config) #ainvoke

                final_message = "Task completed."
                if result.get("messages"):
                    final_message = result["messages"][-1].get("content") or final_message

                # ✅ IMPORTANT: await completion if needed
                await self._maybe_await(
                    updater.complete(
                        message=new_agent_text_message(
                            final_message,
                            task.context_id,
                            task.id,
                        )
                    )
                )

            except Exception as e:
                traceback.print_exc()
                await self._maybe_await(
                    updater.complete(
                        message=new_agent_text_message(
                            f"Error occurred: {type(e).__name__}: {e}",
                            task.context_id,
                            task.id,
                        )
                    )
                )

        except Exception as e:
            traceback.print_exc()
            # Let A2A handle fatal execute errors
            raise

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        task_updater = TaskUpdater(event_queue, context.task_id, context.context_id)
        task_updater.update_status(TaskState.canceled, message=TextPart(text="Task canceled."))


# ---------------------------
# 5) Build the A2A HTTP handler
# ---------------------------
request_handler = DefaultRequestHandler(
    agent_executor=LanggraphAgentExecutor(),  #graph
    task_store=InMemoryTaskStore(),     # stores task state in RAM (use persistent store in prod)
)

# ---------------------------
# 6) Build the A2A Starlette server app
# ---------------------------
server = A2AStarletteApplication(
    agent_card=agent_card,              # describes capabilities, endpoints, etc.
    http_handler=request_handler
)

# ---------------------------
# 7) Run with Uvicorn
# ---------------------------
host = os.environ.get("A2A_HOST", "127.0.0.1")
port = int(os.environ.get("A2A_PORT", "10008"))

if __name__ == "__main__":
    uvicorn.run(server.build(), host=host, port=port)
