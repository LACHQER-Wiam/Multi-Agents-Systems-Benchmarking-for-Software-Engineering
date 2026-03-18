import logging
import asyncio
from uuid import uuid4
import json
import os
import argparse

import httpx

from a2a.client import A2AClient
from a2a.types import MessageSendParams, SendStreamingMessageRequest

from utils.AtoA_architecture_stream import agent_card  # ← IMPORTANT


def load_dataset(dataset_path, language, task):
    if task == "task1":
        path = os.path.join(dataset_path, language, f"{task}_{language}_1.json")
    elif task == "task2":
        path = os.path.join(dataset_path, language, f"{task}_{language}_final.json")
    else:
        path = os.path.join(dataset_path, language, f"{task}_{language}_new_1.json")

    with open(path, "r") as f:
        dataset = json.load(f)

    message_payloads = []

    for i, sample in enumerate(dataset):

        # =========================
        # Construction du prompt selon la tâche
        # =========================

        if task == "task1":
            function = sample["feature_description"]
            code_content = sample["content"]

            prompt = (
                "### Feature Description:\n"
                f"{function}\n\n"
                "### Code Content:\n"
                f"{code_content}\n\n"
            )

        elif task == "task2":
            filenames = sample["files"]
            code_content = sample["content"]

            prompt = (
                "### Filenames:\n"
                f"{', '.join(filenames)}\n\n"
                "### Code Content:\n"
                f"{code_content}\n\n"
            )

        else:  # task4
            description = sample["description"]
            function = sample["function"]
            files = "\n".join(
                [f"- {file['file']}: {file['function']}" for file in sample["files"]]
            )

            # ✅ f-string correctement formée (était une string littérale non interpolée)
            prompt = (
                "### Project Description:\n"
                f"{description}\n\n"
                "### Project Function:\n"
                f"{function}\n\n"
                "### Files:\n"
                f"{files}\n\n"
            )

        # =========================
        # Construction du payload
        # =========================

        payload = {
            "jsonrpc": "2.0",
            "id": i,
            "method": "message/stream",
            "params": {
                "message": {
                    "role": "user",
                    "parts": [
                        {
                            "type": "text",
                            "text": prompt
                        }
                    ],
                    "messageId": str(i)
                },
                "metadata": {
                    "sample_idx": i
                }
            }
        }

        message_payloads.append(payload)

    return message_payloads


####################

def format_save_results(responses, dataset_path, res_dir, task, language, model_name, type_agent="AtoA"):
    # ========================
    # Load dataset (for GT) - MUST match load_dataset()
    # ========================
    if task == "task1":
        path = os.path.join(dataset_path, language, f"{task}_{language}_1.json")
        gt_field = "modified_complete_code"
    elif task == "task2":
        path = os.path.join(dataset_path, language, f"{task}_{language}_final.json")
        gt_field = "gt"
    else:
        path = os.path.join(dataset_path, language, f"{task}_{language}_new_1.json")
        gt_field = "gt"

    with open(path, "r") as f:
        dataset = json.load(f)

    # ========================
    # Create output directory
    # ========================
    save_dir = os.path.join(
        res_dir, task, type_agent, f"{language}/{model_name}-{language}"
    )
    os.makedirs(save_dir, exist_ok=True)

    name = model_name.split("/")[-1]
    evalpath = os.path.join(save_dir, f"{name}_predictions.json")

    print(f"Results directory: {save_dir}")

    # ========================
    # Build final responses
    # ========================
    final_responses = []

    for i, (response, sample) in enumerate(zip(responses, dataset)):
        # response est la string de texte finale collectée depuis le stream
        text = response if isinstance(response, str) else ""

        # Extraire le dernier bloc JSON produit par le modèle
        try:
            last_json_start = text.rfind("{")
            pred_json = json.loads(text[last_json_start:])
        except Exception:
            pred_json = {}

        gt_value = sample.get(gt_field, {})

        result_entry = {
            "idx": sample.get("idx", i),
            "pred": pred_json,
            "gt": gt_value,
        }

        final_responses.append(result_entry)

    # ========================
    # Save results
    # ========================
    with open(evalpath, "w") as f:
        json.dump(final_responses, f, indent=2, ensure_ascii=False)


####################

def _extract_text_from_event(event_data) -> str:
    """
    Extrait le texte depuis n'importe quel type d'événement A2A SSE.
    Retourne une string vide si aucun texte trouvé.
    """
    # Tenter d'atteindre les parts selon la structure de l'objet
    candidates = []

    # Cas 1 : event_data est un Task avec status.message.parts
    status = getattr(event_data, "status", None)
    if status:
        msg = getattr(status, "message", None)
        if msg:
            candidates.append(msg)

    # Cas 2 : event_data est un Message avec parts directement
    if hasattr(event_data, "parts"):
        candidates.append(event_data)

    # Cas 3 : event_data.result (TaskStatusUpdateEvent, etc.)
    result = getattr(event_data, "result", None)
    if result:
        status2 = getattr(result, "status", None)
        if status2:
            msg2 = getattr(status2, "message", None)
            if msg2:
                candidates.append(msg2)
        if hasattr(result, "parts"):
            candidates.append(result)

    text = ""
    for obj in candidates:
        parts = getattr(obj, "parts", []) or []
        for part in parts:
            part_root = getattr(part, "root", part)
            if getattr(part_root, "kind", None) == "text":
                text += part_root.text or ""

    return text


async def stream_one_message(
    client: A2AClient,
    payload: dict,
    logger: logging.Logger
) -> str:
    """
    Envoie un message en mode SSE (message/stream) et retourne
    le texte du dernier événement 'completed' reçu.

    Stratégie :
    - On collecte TOUS les chunks de texte reçus.
    - On garde séparément le texte du dernier événement dont le
      state == "completed" (c'est le résultat final de l'agent).
    - Si aucun état completed n'est trouvé, on retourne tout le texte accumulé.
    """
    message_request = SendStreamingMessageRequest(
        id=str(uuid4()),
        params=MessageSendParams(**payload["params"]),
    )

    accumulated_text = ""
    final_completed_text = ""

    try:
        async for event in client.send_message_streaming(message_request):
            event_data = event.root

            event_kind = getattr(event_data, "kind", None) or type(event_data).__name__
            logger.debug(f"SSE event kind: {event_kind}")

            chunk_text = _extract_text_from_event(event_data)
            if chunk_text:
                accumulated_text += chunk_text
                logger.debug(f"  → chunk text ({len(chunk_text)} chars)")

            # Détecter l'état "completed" pour capturer le message final
            state = None
            status = getattr(event_data, "status", None)
            if status:
                state = getattr(status, "state", None)

            result = getattr(event_data, "result", None)
            if result:
                status2 = getattr(result, "status", None)
                if status2:
                    state = getattr(status2, "state", None)

            if state is not None:
                state_val = state.value if hasattr(state, "value") else str(state)
                logger.debug(f"  → task state: {state_val}")
                if state_val == "completed" and chunk_text:
                    final_completed_text = chunk_text

    except Exception as e:
        logger.error(f"Streaming error for payload id={payload.get('id')}: {type(e).__name__}: {e}")
        return (
            f'{{"messages":[{{"role":"assistant","content":'
            f'"Stream error: {type(e).__name__}: {str(e)}"}}],"next":"complete"}}'
        )

    # Retourner le texte du dernier événement completed, sinon tout le texte accumulé
    result_text = final_completed_text or accumulated_text
    if not result_text:
        logger.warning(f"No text received for payload id={payload.get('id')}")
        result_text = '{"messages":[{"role":"assistant","content":"No output received."}],"next":"complete"}'

    return result_text


async def main(message_payloads):
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    timeout = httpx.Timeout(
        connect=10.0,
        read=300.0,   # SSE peut rester ouvert longtemps
        write=10.0,
        pool=10.0,
    )

    limits = httpx.Limits(
        max_connections=100,
        max_keepalive_connections=20,
    )

    async with httpx.AsyncClient(
        timeout=timeout,
        limits=limits
    ) as httpx_client:

        client = A2AClient(
            httpx_client=httpx_client,
            agent_card=agent_card,
        )

        logger.info("A2AClient initialized with local agent_card.")

        # Lancer toutes les requêtes streaming en parallèle
        # tasks = [
        #     stream_one_message(client, payload, logger)
        #     for payload in message_payloads
        # ]

        responses = []
        for payload in message_payloads:
            responses.append(await stream_one_message(client, payload, logger))
            await asyncio.sleep(10)  # secondes entre chaque requête
        return responses



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run model evaluation via A2A")
    parser.add_argument("--model_name", type=str, required=True, help="Anthropic model name")
    parser.add_argument("--language", type=str, required=True)
    parser.add_argument("--task", type=str, default="task1")
    parser.add_argument("--dataset_path", type=str, default="./data")
    parser.add_argument("--res_dir", type=str, default="./results")
    args = parser.parse_args()

    message_payloads = load_dataset(args.dataset_path, args.language, args.task)
    print("MESSAGE PAYLOADS", message_payloads)
    responses = asyncio.run(main(message_payloads=message_payloads))
    print(responses)
    format_save_results(responses,
                        args.dataset_path,
                        args.res_dir,
                        args.task,
                        args.language,
                        args.model_name)