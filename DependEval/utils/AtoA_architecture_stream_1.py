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


from .prompts_AtoA import build_prompt_AtoA 
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

system_prompt, details, description = build_prompt_AtoA(task)

# =========================
# STATE
# =========================

class State(TypedDict):
    messages: List[Dict]
    analysis: Optional[str]
    critique: Optional[str]
    next: Optional[str]
    rounds: int

if task=='task1':
    class FinalOutput(BaseModel):
        called_code_segment: str 
        invoking_code_segment: str
        feature_description: str
        modified_complete_code: str
         
elif task=='task2':
    class FinalOutput(BaseModel):
        list_dependencies: str
        justification: str
else :
    class FinalOutput(BaseModel):
        dependency_groups: str
        justification: str

# =========================
# CLAUDE WRAPPER
# =========================

class TokenTracker:
    """
    Writes one JSON line per LLM call to a JSONL file so records survive
    across process boundaries (server vs. inference script).
    The file path is set via the TOKEN_LOG_PATH env variable.
    """

    def __init__(self):
        self._current_sample_idx: int = 0

    def _log_path(self) -> str:
        # Derive path from the server's own args so no env var coordination needed
        model_short = model_name.split("/")[-1]
        return f"/tmp/token_usage_{model_short}_{task}_{language}.jsonl"

    def set_sample(self, idx: int):
        self._current_sample_idx = idx

    def record(self, agent_name: str, input_tokens: int, output_tokens: int):
        record = {
            "sample_idx": self._current_sample_idx,
            "agent": agent_name,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
        }
        try:
            with open(self._log_path(), "a") as f:
                f.write(json.dumps(record) + "\n")
        except Exception as e:
            print(f"[TokenTracker] Failed to write record: {e}")

    def load_records(self) -> List[Dict]:
        path = self._log_path()
        if not os.path.exists(path):
            return []
        records = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        records.append(json.loads(line))
                    except Exception:
                        pass
        return records

    def summary(self) -> Dict:
        from collections import defaultdict
        agg: Dict = defaultdict(lambda: {"input_tokens": 0, "output_tokens": 0, "calls": 0})
        for rec in self.load_records():
            ag = rec["agent"]
            agg[ag]["input_tokens"] += rec["input_tokens"]
            agg[ag]["output_tokens"] += rec["output_tokens"]
            agg[ag]["calls"] += 1
        return dict(agg)

    def reset_log(self):
        path = self._log_path()
        if os.path.exists(path):
            os.remove(path)


# Singleton tracker accessible from nodes
token_tracker = TokenTracker()


class ClaudeLLM:

    def __init__(self, model_name="claude-haiku-4-5", temperature=0, max_tokens=8000):
        self.client = anthropic.Client(
            api_key=os.environ.get("ANTHROPIC_API_KEY"),
        )
        self.model_name = model_name
        self.temperature = temperature
        self.max_tokens = max_tokens
        # Current agent context for token attribution
        self._current_agent: str = "unknown"

    def set_agent(self, agent_name: str):
        self._current_agent = agent_name

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

            if role not in {"user", "assistant"}:
                role = "assistant"

            content = content.rstrip()

            filtered_messages.append({
                "role": role,
                "content": content
            })

        return system_prompt, filtered_messages

    def invoke(self, messages, agent_name: str = None):
        system_prompt, filtered_messages = self._prepare_messages(messages)
        agent = agent_name or self._current_agent

        try:
            full_text = ""

            with self.client.messages.stream(
                model=self.model_name,
                max_tokens=self.max_tokens,
                temperature=self.temperature,
                system=system_prompt,
                messages=filtered_messages,
            ) as stream:
                for text_chunk in stream.text_stream:
                    full_text += text_chunk
                # Capture usage from the final message
                final_msg = stream.get_final_message()
                if final_msg and final_msg.usage:
                    token_tracker.record(
                        agent_name=agent,
                        input_tokens=final_msg.usage.input_tokens,
                        output_tokens=final_msg.usage.output_tokens,
                    )

            if full_text:
                return full_text

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



# =========================
# ROUTING FUNCTION
# =========================

def routing(state: State):
    next_node = state.get("next", "supervisor")
    valid_nodes = ["code_analyser", "critic", "complete", "end", "supervisor"]
    next_node_lower = str(next_node).lower().strip()
    if next_node_lower in valid_nodes:
        return next_node_lower
    print(f"⚠️  Invalid route '{next_node}', falling back to supervisor")
    return "supervisor"

# =========================
# NODES
# =========================

def supervisor_node(state: State):
    if state.get("rounds", 0) >= max_rounds:
        return {
            "next": "complete",
            "rounds": state.get("rounds", 0) + 1,
            "messages": state["messages"],
            "analysis": state.get("analysis"),
            "critique": state.get("critique"),
        }

    _parser = PydanticOutputParser(pydantic_object=Router)

    messages = [
        {
            "role": "system",
            "content": system_prompt + "\n" + _parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages, agent_name="supervisor")
    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    print(f"📝 Supervisor raw response: {response_text[:200]}")
    print(f"📝 Supervisor cleaned: {cleaned[:200]}")

    try:
        parsed = _parser.parse(cleaned)
        print(f"✅ Parsed successfully: next={parsed.next}, messages={len(parsed.messages)}")

        if parsed.messages and len(parsed.messages) > 0 and isinstance(parsed.messages[0], dict):
            assistant_message = parsed.messages[0].get("content", cleaned)
        else:
            assistant_message = cleaned

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
        print(f"❌ Parsing error in supervisor: {e}")
        try:
            json_obj = json.loads(cleaned)
            next_value = str(json_obj.get("next", "supervisor")).lower().strip()
        except:
            next_value = "supervisor"

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
    _parser = PydanticOutputParser(pydantic_object=Router)

    messages = [
        {
            "role": "system",
            "content": details["code_analyser"] + "\n" + _parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages, agent_name="code_analyser")
    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    try:
        parsed = _parser.parse(cleaned)

        if parsed.messages and len(parsed.messages) > 0 and isinstance(parsed.messages[0], dict):
            assistant_message = parsed.messages[0].get("content", cleaned)
        else:
            assistant_message = cleaned

        next_value = str(parsed.next).lower().strip() if parsed.next else "supervisor"

        return {
            "messages": state["messages"] + [{"role": "assistant", "content": assistant_message}],
            "next": next_value,
            "rounds": state.get("rounds", 0),
            "analysis": assistant_message,
            "critique": state.get("critique"),
        }

    except Exception as e:
        print(f"❌ Parsing error in code_analyser: {e}")
        try:
            json_obj = json.loads(cleaned)
            next_value = str(json_obj.get("next", "supervisor")).lower().strip()
        except:
            next_value = "supervisor"

        return {
            "messages": state["messages"] + [{"role": "assistant", "content": cleaned}],
            "next": next_value,
            "rounds": state.get("rounds", 0),
            "analysis": cleaned,
            "critique": state.get("critique"),
        }


def critic_node(state: State):
    _parser = PydanticOutputParser(pydantic_object=Router)

    messages = [
        {
            "role": "system",
            "content": details["critic"] + "\n" + _parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages, agent_name="critic")
    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    try:
        parsed = _parser.parse(cleaned)

        if parsed.messages and len(parsed.messages) > 0 and isinstance(parsed.messages[0], dict):
            assistant_message = parsed.messages[0].get("content", cleaned)
        else:
            assistant_message = cleaned

        next_value = str(parsed.next).lower().strip() if parsed.next else "supervisor"

        return {
            "messages": state["messages"] + [{"role": "assistant", "content": assistant_message}],
            "next": next_value,
            "rounds": state.get("rounds", 0),
            "analysis": state.get("analysis"),
            "critique": assistant_message,
        }

    except Exception as e:
        print(f"❌ Parsing error in critic: {e}")
        try:
            json_obj = json.loads(cleaned)
            next_value = str(json_obj.get("next", "supervisor")).lower().strip()
        except:
            next_value = "supervisor"

        return {
            "messages": state["messages"] + [{"role": "assistant", "content": cleaned}],
            "next": next_value,
            "rounds": state.get("rounds", 0),
            "analysis": state.get("analysis"),
            "critique": cleaned,
        }


def finalizer_node(state: State):
    _parser = PydanticOutputParser(pydantic_object=FinalOutput)

    messages = [
        {
            "role": "system",
            "content": details["finalizer"] + "\n" + _parser.get_format_instructions(),
        }
    ] + state["messages"]

    response_text = llm.invoke(messages, agent_name="finalizer")
    cleaned = response_text.replace("```json", "").replace("```", "").strip()

    return {
        "messages": state["messages"] + [{"role": "assistant", "content": cleaned}],
        "next": "complete",
        "rounds": state.get("rounds", 0),
        "analysis": state.get("analysis"),
        "critique": state.get("critique"),
    }


# =========================
# ROUTING HELPERS
# =========================

def route_from_supervisor(state: State) -> str:
    n = (state.get("next") or "").strip().lower()
    if n in {"end", "finish", "done"}:
        return "complete"
    if n not in {"code_analyser", "critic", "complete"}:
        return "code_analyser"
    return n

def route_from_code_analyser(state: State) -> str:
    n = (state.get("next") or "").strip().lower()
    if n in {"end", "finish", "done"}:
        return "complete"
    if n not in {"critic", "supervisor", "complete"}:
        return "supervisor"
    return n

def route_from_critic(state: State) -> str:
    n = (state.get("next") or "").strip().lower()
    if n in {"end", "finish", "done"}:
        return "complete"
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
# SKILLS + AGENT CARD
# =========================

skill_supervisor = AgentSkill(
    id='supervisor',
    name='Supervisor Orchestrator',
    description=(description["supervisor"]),
    tags=['orchestration', 'routing', 'multi-agent']
)

skill_code_analyser = AgentSkill(
    id='code-analyser',
    name='Code Analyzer',
    description=(description["code_analyser"]),
    tags=['code-analysis', 'python', 'bug-detection']
)

skill_critic = AgentSkill(
    id='critic',
    name='Code Critic',
    description=(description["critic"]),
    tags=['code-review', 'critique', 'validation']
)

finalizer_skill = AgentSkill(
    id='finalizer',
    name='Finalizer',
    description=(description["finalizer"]),
    OutputModes=["application/json"],
    tags=['finalization', 'output-generation']
)

agent_card = AgentCard(
    name='Multi-Agent Code Review Agent',
    description=description["global_agent"],
    url='http://localhost:10008/',
    version='1.0.0',
    defaultInputModes=['text'],
    defaultOutputModes=['text'],
    capabilities=AgentCapabilities(
        streaming=True
    ),
    authentication={
        "schemes": ["basic"]
    },
    skills=[skill_code_analyser, skill_critic, skill_supervisor, finalizer_skill]
)


# =========================
# A2A EXECUTOR — streaming via TaskUpdater
# =========================

class LanggraphAgentExecutor(AgentExecutor):
    def __init__(self):
        self.agent = graph

    async def _maybe_await(self, x):
        if inspect.isawaitable(x):
            return await x
        return x

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        try:
            query = context.get_user_input()

            task = context.current_task
            if not task:
                task = new_task(context.message)
                # Publier la création de la tâche — cela ouvre le flux SSE côté serveur
                await self._maybe_await(event_queue.enqueue_event(task))

            print(f"TAAAASK: {task}")

            updater = TaskUpdater(event_queue, task.id, task.context_id)

            # Extract sample index from request context for token tracking
            sample_idx = 0

            # Try to get sample_idx from context metadata
            if hasattr(context, 'metadata') and isinstance(context.metadata, dict):
                sample_idx = context.metadata.get("sample_idx", 0)
                print(f"✅ Sample index from metadata: {sample_idx}")

            # Fallback: try messageId
            if sample_idx == 0:
                try:
                    if hasattr(context, 'message') and context.message:
                        msg_id = getattr(context.message, 'messageId', None)
                        if msg_id:
                            sample_idx = int(str(msg_id).strip())
                            print(f"✅ Sample index from messageId: {sample_idx}")
                except (ValueError, AttributeError, TypeError) as e:
                    print(f"⚠️ Could not extract sample_idx from messageId: {e}")

            # Final fallback: use context_id as hash to ensure uniqueness
            if sample_idx == 0:
                print(f"⚠️ Using default sample_idx=0 (context_id={task.context_id})")

            token_tracker.set_sample(sample_idx)
            print(f"🏷️  Token tracker set to sample_idx={sample_idx}")

            input_data = {
                "messages": [{"role": "user", "content": query}],
                "analysis": None,
                "critique": None,
                "next": None,
                "rounds": 0,
            }
            config = {"configurable": {"thread_id": task.context_id}}

            try:
                final_message = "Task completed."

                # ✅ astream() = AsyncGenerator de {node_name: state_dict}
                # On appelle updater.update_status(working) à chaque nœud pour
                # maintenir le flux SSE ouvert — sans ça, le serveur bascule en JSON.
                async for chunk in self.agent.astream(input_data, config=config):
                    for node_name, node_state in chunk.items():
                        print(f"📡 Node '{node_name}' streaming chunk")

                        if node_state.get("messages"):
                            last_content = node_state["messages"][-1].get("content", "")
                            # Événement intermédiaire visible dans le flux SSE
                            await self._maybe_await(
                                updater.update_status(
                                    TaskState.working,
                                    message=new_agent_text_message(
                                        f"[{node_name}] {last_content[:300]}",
                                        task.context_id,
                                        task.id,
                                    )
                                )
                            )
                            # Garder le dernier message pour la complétion finale
                            final_message = last_content or final_message

                # ✅ Fermer le flux SSE avec l'état "completed"
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
            raise

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        task_updater = TaskUpdater(event_queue, context.task_id, context.context_id)
        task_updater.update_status(TaskState.canceled, message=TextPart(text="Task canceled."))


# =========================
# A2A SERVER
# =========================

request_handler = DefaultRequestHandler(
    agent_executor=LanggraphAgentExecutor(),
    task_store=InMemoryTaskStore(),
)

server = A2AStarletteApplication(
    agent_card=agent_card,
    http_handler=request_handler
)

host = os.environ.get("A2A_HOST", "127.0.0.1")
port = int(os.environ.get("A2A_PORT", "10008"))

if __name__ == "__main__":
    uvicorn.run(server.build(), host=host, port=port)