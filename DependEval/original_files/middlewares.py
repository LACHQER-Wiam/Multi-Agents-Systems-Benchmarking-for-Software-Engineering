from typing import Callable
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse


class TokenCounterMiddleware:
    def __init__(self):
        self.last_input_tokens = 0
        self.last_output_tokens = 0

    @wrap_model_call
    def __call__(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ) -> ModelResponse:

        # ---- Appel réel du modèle ----
        response = handler(request)

        # ---- Récupération des tokens ----
        input_tokens = 0
        output_tokens = 0

        if response.llm_output and "token_usage" in response.llm_output:
            usage = response.llm_output["token_usage"]
            input_tokens = usage.get("prompt_tokens", 0)
            output_tokens = usage.get("completion_tokens", 0)

        # Stockage interne (optionnel)
        self.last_input_tokens = input_tokens
        self.last_output_tokens = output_tokens

        print(
            f"[LLM CALL] Input tokens: {input_tokens} | Output tokens: {output_tokens}"
        )

        return response