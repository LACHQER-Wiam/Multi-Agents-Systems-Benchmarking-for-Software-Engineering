"""
Script de diagnostic : envoie des requêtes brutes au serveur A2A
et affiche les headers + body exacts pour comprendre pourquoi
le serveur répond en application/json au lieu de text/event-stream.
"""

import asyncio
import httpx
import json


SERVER_URL = "http://localhost:10008"


async def main():
    async with httpx.AsyncClient(timeout=60.0) as client:

        # ─────────────────────────────────────────
        # 1) Inspecter l'AgentCard publiée par le serveur
        # ─────────────────────────────────────────
        print("=" * 60)
        print("1) GET /.well-known/agent.json")
        print("=" * 60)
        try:
            r = await client.get(f"{SERVER_URL}/.well-known/agent.json")
            print(f"Status: {r.status_code}")
            card = r.json()
            print(json.dumps(card, indent=2))
            streaming_cap = card.get("capabilities", {}).get("streaming", False)
            print(f"\n>>> streaming capability declaree: {streaming_cap}")
        except Exception as e:
            print(f"ERROR: {e}")

        print()

        # ─────────────────────────────────────────
        # 2) Tester message/send (non-streaming)
        # ─────────────────────────────────────────
        print("=" * 60)
        print("2) POST /  — method: message/send  (non-streaming)")
        print("=" * 60)
        payload_send = {
            "jsonrpc": "2.0",
            "id": "test-send",
            "method": "message/send",
            "params": {
                "message": {
                    "role": "user",
                    "parts": [{"type": "text", "text": "Hello, respond in one sentence."}],
                    "messageId": "msg-send-1"
                },
                "metadata": {}
            }
        }
        try:
            r = await client.post(
                SERVER_URL,
                json=payload_send,
                headers={"Content-Type": "application/json"},
            )
            print(f"Status: {r.status_code}")
            print(f"Content-Type: {r.headers.get('content-type')}")
            print(f"Body (first 500 chars): {r.text[:500]}")
        except Exception as e:
            print(f"ERROR: {e}")

        print()

        # ─────────────────────────────────────────
        # 3) Tester message/stream (SSE) - requete brute
        # ─────────────────────────────────────────
        print("=" * 60)
        print("3) POST /  — method: message/stream  (SSE brute)")
        print("=" * 60)
        payload_stream = {
            "jsonrpc": "2.0",
            "id": "test-stream",
            "method": "message/stream",
            "params": {
                "message": {
                    "role": "user",
                    "parts": [{"type": "text", "text": "Hello, respond in one sentence."}],
                    "messageId": "msg-stream-1"
                },
                "metadata": {}
            }
        }
        try:
            async with client.stream(
                "POST",
                SERVER_URL,
                json=payload_stream,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream",
                },
            ) as r:
                print(f"Status: {r.status_code}")
                print(f"Content-Type: {r.headers.get('content-type')}")
                print(f"All response headers: {dict(r.headers)}")
                print("\nSSE chunks received:")
                chunk_count = 0
                async for line in r.aiter_lines():
                    if line:
                        print(f"  [{chunk_count}] {line[:300]}")
                        chunk_count += 1
                        if chunk_count > 20:
                            print("  ... (truncated)")
                            break
        except Exception as e:
            print(f"ERROR: {type(e).__name__}: {e}")

        print()

        # ─────────────────────────────────────────
        # 4) Verifier routes exposees
        # ─────────────────────────────────────────
        for path in ["/stream", "/message/stream", "/rpc"]:
            print(f"Testing POST {path} ...")
            try:
                r = await client.post(
                    f"{SERVER_URL}{path}",
                    json=payload_stream,
                    headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
                    timeout=5.0,
                )
                print(f"  Status: {r.status_code}, Content-Type: {r.headers.get('content-type')}")
            except Exception as e:
                print(f"  ERROR: {type(e).__name__}: {e}")


if __name__ == "__main__":
    asyncio.run(main())