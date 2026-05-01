#!/usr/bin/env python3
"""
rollie curate — generate a ChatML JSONL training dataset from one or more sources.

Called by rollie.fish with sys.argv arguments. All heavy imports are deferred
so startup is fast for --help.
"""

import argparse
import json
import os
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        prog="rollie curate",
        description="Generate a ChatML JSONL training dataset.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Output format (ChatML JSONL):
  {"text": "<|im_start|>user\\n...<|im_end|>\\n<|im_start|>assistant\\n...<|im_end|>"}

Examples:
  rollie curate --persona ./persona.md --output ./out/
  rollie curate --code ~/myproject/ --files ~/docs/ --output ~/datasets/stack/
  rollie curate --repo https://github.com/org/repo --output ./out/
  rollie curate --db sqlite:///mydb.db --output ./out/
        """,
    )

    parser.add_argument("--code",    action="append", metavar="PATH",   default=[], help="Local codebase directory")
    parser.add_argument("--repo",    action="append", metavar="URL",    default=[], help="GitHub repo URL (shallow clone)")
    parser.add_argument("--db",      action="append", metavar="CONN",   default=[], help="SQLite or PostgreSQL connection string")
    parser.add_argument("--files",   action="append", metavar="PATH",   default=[], help="PDF/DOCX/MD/TXT files or directory")
    parser.add_argument("--persona", action="append", metavar="FILE",   default=[], help="Agency-agents-format persona markdown")
    parser.add_argument("--output",  metavar="DIR",   default="",       help="Output directory (default: ~/rollie-workspace/datasets/<auto>/)")
    parser.add_argument("--model",   metavar="MODEL", default="",       help="Ollama model (overrides config)")
    parser.add_argument("--per-chunk", type=int, default=5,            metavar="N", help="Q&A pairs per chunk (default: 5)")
    parser.add_argument("--quality-threshold", type=int, default=3,   metavar="N", help="Min quality score 1–5 (default: 3)")
    parser.add_argument("--no-quality-pass", action="store_true",      help="Skip quality filtering")
    parser.add_argument("--resume",  action="store_true",              help="Resume a previous interrupted run")

    args = parser.parse_args()

    if not any([args.code, args.repo, args.db, args.files, args.persona]):
        parser.print_help()
        sys.exit(1)

    model = args.model or _read_config_model()
    if not model:
        _die(
            "No curation model configured. Run:\n"
            "  rollie --set-data-curation-model\n"
            "or pass --model <ollama-model-name>"
        )

    output_dir = Path(args.output) if args.output else _auto_output_dir()
    output_dir.mkdir(parents=True, exist_ok=True)
    out_file = output_dir / "data.jsonl"

    print(f"[curate] Model:  {model}", flush=True)
    print(f"[curate] Output: {out_file}", flush=True)
    print(f"[curate] Quality threshold: {args.quality_threshold} (skip={args.no_quality_pass})", flush=True)
    print(flush=True)

    all_pairs: list[dict] = []

    # ── sources ──────────────────────────────────────────────────────────────

    for code_path in args.code:
        print(f"[curate] Ingesting codebase: {code_path}", flush=True)
        from sources.codebase import ingest as ingest_code
        chunks = ingest_code(code_path)
        print(f"[curate]   → {len(chunks)} chunks", flush=True)
        pairs = _process_chunks(chunks, model, args.per_chunk, args.quality_threshold, args.no_quality_pass)
        all_pairs.extend(pairs)

    for repo_url in args.repo:
        print(f"[curate] Ingesting repo: {repo_url}", flush=True)
        from sources.repo import ingest as ingest_repo
        chunks = ingest_repo(repo_url)
        print(f"[curate]   → {len(chunks)} chunks", flush=True)
        pairs = _process_chunks(chunks, model, args.per_chunk, args.quality_threshold, args.no_quality_pass)
        all_pairs.extend(pairs)

    for conn in args.db:
        print(f"[curate] Ingesting database: {conn}", flush=True)
        from sources.database import ingest as ingest_db
        chunks = ingest_db(conn)
        print(f"[curate]   → {len(chunks)} chunks", flush=True)
        pairs = _process_chunks(chunks, model, args.per_chunk, args.quality_threshold, args.no_quality_pass)
        all_pairs.extend(pairs)

    for files_path in args.files:
        print(f"[curate] Ingesting files: {files_path}", flush=True)
        from sources.files import ingest as ingest_files
        chunks = ingest_files(files_path)
        print(f"[curate]   → {len(chunks)} chunks", flush=True)
        pairs = _process_chunks(chunks, model, args.per_chunk, args.quality_threshold, args.no_quality_pass)
        all_pairs.extend(pairs)

    for persona_path in args.persona:
        print(f"[curate] Ingesting persona: {persona_path}", flush=True)
        from sources.persona import ingest as ingest_persona
        raw_pairs = ingest_persona(persona_path, model, n_per_topic=args.per_chunk)
        print(f"[curate]   → {len(raw_pairs)} raw pairs", flush=True)
        if not args.no_quality_pass:
            from quality_pass import filter_pairs
            raw_pairs = filter_pairs(raw_pairs, model, threshold=args.quality_threshold)
        all_pairs.extend(raw_pairs)

    # ── write output ─────────────────────────────────────────────────────────

    if not all_pairs:
        print("[curate] No pairs generated. Check your sources and model.", flush=True)
        sys.exit(1)

    written = 0
    with open(out_file, "w", encoding="utf-8") as f:
        for pair in all_pairs:
            system = pair.get("system", "")
            question = pair["question"]
            answer = pair["answer"]

            if system:
                text = (
                    f"<|im_start|>system\n{system}<|im_end|>\n"
                    f"<|im_start|>user\n{question}<|im_end|>\n"
                    f"<|im_start|>assistant\n{answer}<|im_end|>"
                )
            else:
                text = (
                    f"<|im_start|>user\n{question}<|im_end|>\n"
                    f"<|im_start|>assistant\n{answer}<|im_end|>"
                )

            f.write(json.dumps({"text": text}, ensure_ascii=False) + "\n")
            written += 1

    print(flush=True)
    print(f"[curate] ✓ Done — {written} pairs written to {out_file}", flush=True)


def _process_chunks(
    chunks: list[dict],
    model: str,
    per_chunk: int,
    threshold: int,
    skip_quality: bool,
) -> list[dict]:
    from qa_generator import generate_qa_pairs

    all_pairs = []
    for i, chunk in enumerate(chunks):
        print(f"[curate]   chunk {i+1}/{len(chunks)}: generating Q&A...", flush=True)
        pairs = generate_qa_pairs(chunk["content"], model, n=per_chunk)
        if not skip_quality and pairs:
            from quality_pass import filter_pairs
            pairs = filter_pairs(pairs, model, threshold=threshold)
        all_pairs.extend(pairs)

    return all_pairs


def _read_config_model() -> str:
    config_file = Path.home() / ".config" / "rollie" / "data_curation_model"
    if config_file.exists():
        return config_file.read_text().strip()
    return ""


def _auto_output_dir() -> Path:
    import time
    name = f"dataset-{int(time.time())}"
    return Path.home() / "rollie-workspace" / "datasets" / name


def _die(msg: str):
    print(f"[curate] Error: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


if __name__ == "__main__":
    main()
