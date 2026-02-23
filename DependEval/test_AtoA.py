import logging
import asyncio
from typing import Any
from uuid import uuid4

import httpx

from a2a.client import A2AClient
from a2a.types import MessageSendParams, SendMessageRequest

from inference_AtoA import agent_card  # ← IMPORTANT


async def main() -> None:
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    async with httpx.AsyncClient() as httpx_client:

        # ✅ Utiliser directement l'agent_card local
        client = A2AClient(
            httpx_client=httpx_client,
            agent_card=agent_card,
        )

        logger.info("A2AClient initialized with local agent_card.")

        # 🔥 Envoie du message adapté à ton agent
        send_message_payload: dict[str, Any] = {
            "message": {
                "role": "user",
                "parts": [
                    {
                        "kind": "text",
                        "text": """
def add(a, b):
    return a - b
"""
                    }
                ],
                "messageId": uuid4().hex,
            },
        }

        # Use non-streaming request since agent has streaming=False
        message_request = SendMessageRequest(
            id=str(uuid4()),
            params=MessageSendParams(**send_message_payload),
        )

        response = await client.send_message(message_request)

        print("Response received:")
        print(response.model_dump(mode="json", exclude_none=True))


if __name__ == "__main__":
    asyncio.run(main())