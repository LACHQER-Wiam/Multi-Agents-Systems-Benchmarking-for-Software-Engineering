import requests
import json

# URL de ton serveur A2A
URL = "http://localhost:8000/" #rpc

# Payload JSON-RPC conforme A2A
payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "message/stream",  #/stream. send

    "params": {
    "message": {
      "role": "user",
      "parts": [
        {
          "type": "text",
          "text":"""Please analyze this Python function: def add(a, b):return a - b"""
        }
      ],
      "messageId": "test"
    },
    "metadata": {}
  }
}
#     "params": {
#         "input": """Please analyze this Python function:

# def add(a, b):
#     return a - b
# """
#     }
# }

try:
    response = requests.post(URL, json=payload)

    print("Status Code:", response.status_code)
    print("Headers:", response.headers) #json.dumps(response.json(), indent=2)

    for line in response.iter_lines():
      print("RAW LINE:", line)
      if not line:
          continue

      decoded = line.decode("utf-8")

      # SSE format → chaque message commence par "data: "
      if decoded.startswith("data: "):
          content = decoded.replace("data: ", "")

          # Fin du stream
          if content == "[DONE]":
              break

          try:
              data = json.loads(content)

              # A2A final event
              if data.get("type") == "task.complete":
                  final_answer = data["data"]["message"]["parts"][0]["text"]

          except json.JSONDecodeError:
              pass

    # print("\nFINAL ANSWER:\n")
    # print(final_answer)

except Exception as e:
    print("Error while calling A2A agent:", e)