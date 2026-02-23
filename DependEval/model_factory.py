"""
Fabrique de modèles LLM : instancie le bon ChatModel selon le provider.

Rend inference_ReAct.py compatible avec n'importe quelle API LLM (OpenAI,
Anthropic, Google, etc.) via une interface unique. LangChain fournit
BaseChatModel pour tous les providers ; create_agent accepte n'importe
quel modèle conforme à cette interface.
"""

import os
from typing import Any, Optional
from pydantic import create_model
from typing import List, Any, Optional
from langchain.agents.structured_output import ProviderStrategy
from dotenv import load_dotenv
load_dotenv() 

# Type hint pour le modèle (BaseChatModel de LangChain)
ChatModel = Any


def create_llm(
    provider: str,
    model_name: str,
    *,
    temperature: float = 0.0,
    max_tokens: Optional[int] = None,
    api_key: Optional[str] = None,
    **kwargs: Any,
) -> ChatModel:
    """
    Crée un modèle LLM LangChain selon le provider.

    Args:
        provider: "openai", "anthropic", "google", etc.
        model_name: Nom du modèle (ex. "gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro").
        temperature: Température pour la génération.
        max_tokens: Nombre max de tokens en sortie.
        api_key: Clé API (ou via variable d'env : OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.).
        **kwargs: Arguments additionnels passés au constructeur du modèle.

    Returns:
        Instance de BaseChatModel (ChatOpenAI, ChatAnthropic, etc.).

    Raises:
        ValueError: Si le provider n'est pas supporté ou le package n'est pas installé.
    """
    provider = provider.lower().strip()
    common = {"temperature": temperature, "model": model_name}
    if max_tokens is not None:
        common["max_tokens"] = max_tokens

    if provider in ("openai", "azure_openai"):
        try:
            from langchain_openai import ChatOpenAI
        except ImportError:
            raise ValueError(
                "Provider 'openai' requires: pip install langchain-openai. "
                "Set OPENAI_API_KEY or pass api_key."
            )
        key = api_key or os.environ.get("OPENAI_API_KEY", "")
        return ChatOpenAI(api_key=key or None, **common, **kwargs)

    if provider == "anthropic":
        try:
            from langchain_anthropic import ChatAnthropic
        except ImportError:
            raise ValueError(
                "Provider 'anthropic' requires: pip install langchain-anthropic. "
                "Set ANTHROPIC_API_KEY or pass api_key."
            )
        key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        return ChatAnthropic(api_key=key or None, **common, **kwargs)

    if provider in ("google", "gemini"):
        try:
            from langchain_google_genai import ChatGoogleGenerativeAI
        except ImportError:
            raise ValueError(
                "Provider 'google' requires: pip install langchain-google-genai. "
                "Set GOOGLE_API_KEY or pass api_key."
            )
        key = api_key or os.environ.get("GOOGLE_API_KEY", "")
        extra = dict(kwargs)
        if max_tokens is not None:
            extra["max_output_tokens"] = max_tokens
        return ChatGoogleGenerativeAI(
            google_api_key=key or None,
            model=model_name,
            temperature=temperature,
            **extra,
        )

    raise ValueError(
        f"Unknown provider: '{provider}'. "
        "Supported: openai, anthropic, google."
    )


SCHEMAS = {
    "task1": {
        "type": "object",
        "properties": {
            "called_code_segment": {"type": "string"},
            "invoking_code_segment": {"type": "string"},
            "feature_description": {"type": "string"},
            "modified_complete_code": {"type": "string"}
        },
        "required": ["called_code_segment", "invoking_code_segment", "feature_description", "modified_complete_code"],
        "additionalProperties": False
    },
    "task2": {
        "type": "object",
        "properties": {
            "list_dependencies": {"type": "array", "items": {"type": "string"}}
        },
        "required": ["list_dependencies"],
        "additionalProperties": False
    },
    "task4": {
        "type": "object",
        "properties": {
            "dependency_groups": {
                "type": "array",
                "items": {"type": "array", "items": {"type": "string"}}
            }
        },
        "required": ["dependency_groups"],
        "additionalProperties": False
    }
}


def get_response_format(task: str, provider: str):
    if task == "task2":
        schema = create_model("Task2Schema", list_dependencies=(List[str], ...))
    elif task == "task4":
        schema = create_model("Task4Schema", dependency_groups=(List[List[str]], ...))
    elif task == "task1":
        schema = create_model("Task1Schema",
            called_code_segment=(str, ...),
            invoking_code_segment=(str, ...),
            feature_description=(str, ...),
            modified_complete_code=(str, ...)
        )
    else:
        return None
        
    return ProviderStrategy(schema)    
    