import os
import re
import json
import asyncio
from typing import Any, Dict, List, Tuple, Optional

from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langchain_core.prompts import ChatPromptTemplate
from langchain.agents import create_openai_tools_agent, AgentExecutor

def _base_dir() -> str:
    return os.environ.get("AGENT_BASE_DIR", ".")

def _safe_join(rel_path: str) -> str:
    base = os.path.abspath(_base_dir())
    full = os.path.abspath(os.path.join(base, rel_path))
    if not full.startswith(base):
        raise ValueError("Path outside AGENT_BASE_DIR is not allowed.")
    return full

@tool("list_dir")
def list_dir(path: str) -> str:
    """List files/directories in a relative path (from AGENT_BASE_DIR)."""
    full = _safe_join(path)
    if not os.path.isdir(full):
        return f"Not a directory: {path}"
    return "\n".join(sorted(os.listdir(full)))

@tool("read_file")
def read_file(path: str) -> str:
    """Read a text file (relative to AGENT_BASE_DIR)."""
    full = _safe_join(path)
    if not os.path.exists(full):
        return f"File not found: {path}"
    if os.path.isdir(full):
        return f"Is a directory: {path}"
    with open(full, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

@tool("grep")
def grep(query: str) -> str:
    """
    Search for a regex pattern in files under AGENT_BASE_DIR.
    Input format: 'pattern ||| path' (path optional, default '.').
    Example: 'def foo\\( ||| src'
    """
    parts = [p.strip() for p in query.split("|||")]
    pattern = parts[0]
    rel_root = parts[1] if len(parts) > 1 and parts[1] else "."
    root = _safe_join(rel_root)

    if not os.path.isdir(root):
        return f"Not a directory: {rel_root}"

    try:
        rx = re.compile(pattern)
    except re.error as e:
        return f"Invalid regex: {e}"

    hits: List[str] = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if not fn.endswith((".py", ".md", ".txt", ".json", ".yml", ".yaml")):
                continue
            fp = os.path.join(dirpath, fn)
            try:
                with open(fp, "r", encoding="utf-8", errors="replace") as f:
                    for i, line in enumerate(f, 1):
                        if rx.search(line):
                            rel = os.path.relpath(fp, _base_dir())
                            hits.append(f"{rel}:{i}:{line.rstrip()}")
                            if len(hits) >= 200:
                                return "\n".join(hits) + "\n[TRUNCATED]"
            except Exception:
                continue

    return "\n".join(hits) if hits else "No matches."

def _extract_schema(extra_body: Dict[str, Any]) -> Dict[str, Any]:
    # compatible avec ton inference_api.py : extra_body["output_format"]["schema"]
    return extra_body["output_format"]["schema"]

async def run_agent_with_tools(
    prompt: str,
    extra_body: Dict[str, Any],
    model_name: str,
    temperature: float = 0.0,
) -> Tuple[Any, Dict[str, int]]:
    """
    Retourne (parsed, usage) comme ton _call_openai.
    - parsed: dict si JSON ok, sinon string fallback
    - usage: on laisse à 0 pour l’instant (LangSmith track tout; tokens optionnel plus tard)
    """
    max_steps = int(os.environ.get("AGENT_MAX_STEPS", "8"))
    schema = _extract_schema(extra_body)

    llm = ChatOpenAI(model=model_name, temperature=temperature)

    tools = [list_dir, read_file, grep]

    agent_prompt = ChatPromptTemplate.from_messages([
        ("system",
         "You are a software engineering assistant. "
         "Use tools when helpful (codebase browsing, search). "
         "At the end, output ONLY valid JSON matching the required schema. "
         "No markdown, no extra text."),
        ("human", "{input}"),
        ("placeholder", "{agent_scratchpad}"),
    ])

    agent = create_openai_tools_agent(llm=llm, tools=tools, prompt=agent_prompt)
    executor = AgentExecutor(
        agent=agent,
        tools=tools,
        verbose=False,
        max_iterations=max_steps,
        return_intermediate_steps=False,
    )

    def _invoke_agent():
        return executor.invoke({"input": prompt})

    result = await asyncio.to_thread(_invoke_agent)
    text = (result.get("output") or "").strip()

    # Hardening: re-parse JSON (agent peut parfois ajouter des espaces)
    try:
        parsed = json.loads(text) if text else ""
    except Exception:
        parsed = text

    usage = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
    return parsed, usage