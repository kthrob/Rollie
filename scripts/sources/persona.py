"""
Persona source: parse an agency-agents-format markdown persona and generate
synthetic conversations that embody it.
"""

import re
import httpx

OLLAMA_BASE = "http://localhost:11434"


def ingest(persona_path: str, model: str, n_per_topic: int = 5, timeout: int = 180) -> list[dict]:
    """
    Parse a persona markdown file, derive a system prompt, seed topics, and
    generate synthetic user↔assistant conversations.

    Returns list of {system, question, answer} dicts.
    """
    with open(persona_path, "r", encoding="utf-8") as f:
        md = f.read()

    system_prompt = _extract_system_prompt(md)
    topics = _seed_topics(md, model, timeout)

    pairs = []
    for topic in topics:
        new_pairs = _generate_conversation(topic, system_prompt, model, n_per_topic, timeout)
        for p in new_pairs:
            p["system"] = system_prompt
        pairs.extend(new_pairs)

    return pairs


def _extract_system_prompt(md: str) -> str:
    """
    Derive a system prompt from the persona markdown.
    Looks for sections: Identity/Mission/Role/Critical Rules/Communication Style.
    Falls back to the full document if none match.
    """
    sections = {}
    current = None
    for line in md.splitlines():
        heading = re.match(r"^#+\s+(.+)", line)
        if heading:
            current = heading.group(1).strip()
            sections[current] = []
        elif current is not None:
            sections[current].append(line)

    wanted = ["Identity", "Mission", "Role", "Critical Rules", "Communication Style"]
    parts = []
    for key in wanted:
        for section_name, lines in sections.items():
            if key.lower() in section_name.lower():
                body = "\n".join(lines).strip()
                if body:
                    parts.append(f"## {section_name}\n{body}")
                break

    if parts:
        return "\n\n".join(parts)

    return md.strip()[:2000]


def _seed_topics(md: str, model: str, timeout: int) -> list[str]:
    """Ask the curation model to generate 10 realistic conversation topics for this persona."""
    prompt = (
        "You are helping create training data. Read this persona description and "
        "generate 10 realistic, diverse topics or questions a user might bring to "
        "this persona. Output one topic per line, no numbering or bullets.\n\n"
        f"Persona:\n{md[:3000]}"
    )
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }
    try:
        resp = httpx.post(f"{OLLAMA_BASE}/api/chat", json=payload, timeout=timeout)
        resp.raise_for_status()
        text = resp.json()["message"]["content"].strip()
        topics = [t.strip("- •*0123456789.) ") for t in text.splitlines() if t.strip()]
        return [t for t in topics if t][:15]
    except Exception as e:
        print(f"[persona] topic seeding error: {e}", flush=True)
        return ["Help me with my work", "What are best practices here?", "Explain your approach"]


def _generate_conversation(
    topic: str,
    system_prompt: str,
    model: str,
    n: int,
    timeout: int,
) -> list[dict]:
    """Generate n realistic user↔assistant exchange pairs for this topic."""
    prompt = (
        f"You are embodying the persona described below. Generate {n} realistic "
        f"user message + assistant response pairs on the topic: \"{topic}\".\n\n"
        "Output a JSON array only:\n"
        '[{"question": "user message", "answer": "assistant response"}, ...]\n\n'
        f"Persona system prompt:\n{system_prompt[:2000]}"
    )
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }
    try:
        resp = httpx.post(f"{OLLAMA_BASE}/api/chat", json=payload, timeout=timeout)
        resp.raise_for_status()
        text = resp.json()["message"]["content"].strip()
    except Exception as e:
        print(f"[persona] generation error for topic '{topic}': {e}", flush=True)
        return []

    import json, re as _re
    text = _re.sub(r"```(?:json)?\s*", "", text)
    text = _re.sub(r"```", "", text).strip()
    start, end = text.find("["), text.rfind("]")
    if start == -1 or end == -1:
        return []
    try:
        pairs = json.loads(text[start:end + 1])
        return [p for p in pairs if isinstance(p, dict) and "question" in p and "answer" in p]
    except Exception:
        return []
