"""
Middlewares compatibles avec l'agent LangChain (OpenAI, etc.).

Chaque middleware utilise l'API standard LangChain (wrap_model_call, ModelRequest,
ModelResponse) et lit response.llm_output["token_usage"], fourni par OpenAI
et d'autres backends. Aucune dépendance à un fournisseur spécifique.
"""

from typing import Callable, Any, Dict, List
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from langchain.agents.middleware import AgentMiddleware

class TokenCounterMiddleware(AgentMiddleware):
    """
    Affiche les tokens par appel LLM, cumule le total, et stocke l'historique des appels.

    - Par appel : log [LLM CALL #k] Input tokens: X | Output tokens: Y
    - Total : total_input_tokens, total_output_tokens (cumulés)
    - Historique : calls = liste de dicts (call_num, input_tokens, output_tokens, total_tokens)
    """

    def __init__(self) -> None:
        self.last_input_tokens = 0
        self.last_output_tokens = 0
        self.total_input_tokens = 0
        self.total_output_tokens = 0

        # NEW: historique des appels LLM (réinitialisé à chaque reset_totals)
        self.calls: List[Dict[str, Any]] = []

    def reset_totals(self) -> None:
        """Réinitialise les totaux + l'historique (avant chaque agent.invoke pour mesurer par item)."""
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.calls = []

    @wrap_model_call
    def __call__(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ) -> ModelResponse:
        response = handler(request)

        input_tokens = 0
        output_tokens = 0
        if response.llm_output and "token_usage" in response.llm_output:
            usage = response.llm_output["token_usage"]
            input_tokens = usage.get("prompt_tokens", 0)
            output_tokens = usage.get("completion_tokens", 0)

        self.last_input_tokens = int(input_tokens)
        self.last_output_tokens = int(output_tokens)
        self.total_input_tokens += int(input_tokens)
        self.total_output_tokens += int(output_tokens)

        call_num = len(self.calls) + 1
        self.calls.append({
            "call_num": call_num,
            "input_tokens": int(input_tokens),
            "output_tokens": int(output_tokens),
            "total_tokens": int(input_tokens + output_tokens),
        })

        print(f"[LLM CALL #{call_num}] Input tokens: {input_tokens} | Output tokens: {output_tokens}")

        return response
    
    
    def wrap_tool_call(
        self,
        request: Any,
        handler: Callable[[Any], Any],
    ) -> Any:
        return handler(request)

    
    async def awrap_tool_call(
        self,
        request: Any,
        handler: Callable[[Any], Any],
    ) -> Any:
        return await handler(request)