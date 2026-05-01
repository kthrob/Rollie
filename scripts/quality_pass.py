"""Rate and filter Q&A pairs using a second Ollama call."""

import re
import httpx

OLLAMA_BASE = "http://localhost:11434"


def rate_pair(question: str, answer: str, model: str, timeout: int = 60) -> int:
    """Return a quality score 1–5, or 0 on failure."""
    prompt = (
        "Rate the following Q&A pair on a scale of 1 to 5 considering:\n"
        "  1 = Poor (irrelevant, inaccurate, or unclear)\n"
        "  5 = Excellent (relevant, accurate, and clearly written)\n\n"
        f"Question: {question}\n"
        f"Answer: {answer}\n\n"
        "Output a single integer 1–5 with no other text."
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
        m = re.search(r"\b([1-5])\b", text)
        return int(m.group(1)) if m else 0
    except Exception:
        return 0


def filter_pairs(
    pairs: list[dict],
    model: str,
    threshold: int = 3,
) -> list[dict]:
    """Return only pairs scoring >= threshold."""
    kept = []
    for p in pairs:
        score = rate_pair(p["question"], p["answer"], model)
        if score >= threshold:
            kept.append(p)
        else:
            print(
                f"[quality_pass] dropped (score={score}): {p['question'][:60]}",
                flush=True,
            )
    return kept
