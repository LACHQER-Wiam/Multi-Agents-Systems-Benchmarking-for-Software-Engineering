import anthropic
from dotenv import load_dotenv
import os

load_dotenv()

api_key = os.getenv("API_KEY")

client = anthropic.Client(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))

response = client.messages.create(
    model="claude-opus-4-6",
    max_tokens=100,
    messages=[{"role": "user", "content": "explain the theory of relativity in simple terms."}]
)

# print(response.content[0].text)
print(anthropic.HUMAN_PROMPT)