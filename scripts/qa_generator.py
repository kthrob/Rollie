"""Generate Q&A pairs from text chunks using a local Ollama model."""

import json
import re
import httpx

OLLAMA_BASE = "http://localhost:11434"


def generate_qa_pairs(
    chunk: str,
    model: str,
    n: int = 5,
    timeout: int = 120,
) -> list[dict]:
    """Return up to `n` {question, answer} dicts for the given chunk."""
    prompt = (
        f"You are a training data generator. Read the following content carefully "
        f"and generate exactly {n} diverse, self-contained Q&A pairs that would help "
        f"someone learn from this material. Each question must be answerable from the "
        f"content alone.\n\n"
        f"Output a JSON array only — no other text:\n"
        f'[{{"question": "...", "answer": "..."}}, ...]\n\n'
        f"Content:\n{chunk}"
    )

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }

    try:
        resp = httpx.post(
            f"{OLLAMA_BASE}/api/chat",
            json=payload,
            timeout=timeout,
        )
        resp.raise_for_status()
        text = resp.json()["message"]["content"].strip()
    except (httpx.HTTPError, KeyError, ValueError) as e:
        print(f"[qa_generator] Ollama error: {e}", flush=True)
        return []

    return _parse_json_array(text)


def _parse_json_array(text: str) -> list[dict]:
    """Extract the first JSON array from model output; tolerate markdown fences."""
    text = re.sub(r"```(?:json)?\s*", "", text)
    text = re.sub(r"```", "", text)
    text = text.strip()

    # Find the outermost [ ... ]
    start = text.find("[")
    end = text.rfind("]")
    if start == -1 or end == -1:
        return []

    try:
        pairs = json.loads(text[start : end + 1])
        return [
            p for p in pairs
            if isinstance(p, dict) and "question" in p and "answer" in p
        ]
    except json.JSONDecodeError:
        return []
