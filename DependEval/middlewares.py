from langchain.agents.middleware import AgentMiddleware, after_model, ModelResponse
from langchain.agents.middleware import wrap_tool_call
from typing import Callable, Any, Dict, List

class TokenCounterMiddleware(AgentMiddleware):

    def __init__(self) -> None:
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.calls: List[Dict[str, Any]] = []

    def reset_totals(self) -> None:
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.calls = []

    @after_model
    def __call__(self, response: ModelResponse) -> ModelResponse:
        print("DEBUG: after_model called!")
        input_tokens = 0
        output_tokens = 0

        # Les tokens sont dans usage_metadata des messages résultat
        for msg in response.result:
            usage = getattr(msg, "usage_metadata", None)
            if usage:
                input_tokens += usage.get("input_tokens", 0)
                output_tokens += usage.get("output_tokens", 0)

        self.total_input_tokens += input_tokens
        self.total_output_tokens += output_tokens
        call_num = len(self.calls) + 1
        self.calls.append({
            "call_num": call_num,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
        })
        print(f"[LLM CALL #{call_num}] Input: {input_tokens} | Output: {output_tokens}")
        return response

    def wrap_tool_call(self, request: Any, handler: Callable) -> Any:
        return handler(request)

    async def awrap_tool_call(self, request: Any, handler: Callable) -> Any:
        return await handler(request)