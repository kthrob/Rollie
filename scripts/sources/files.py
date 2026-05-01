"""
Files source: ingest PDF, DOCX, Markdown, and plain text files into chunks.
"""

import os
from pathlib import Path

CHUNK_SIZE = 1500
CHUNK_OVERLAP = 200


def ingest(path: str) -> list[dict]:
    """
    Walk `path` (file or directory) and return list of {content, source} dicts.
    Supported: .pdf, .docx, .md, .mdx, .rst, .txt
    """
    p = Path(path)
    files = []
    if p.is_file():
        files = [p]
    elif p.is_dir():
        for ext in ("*.pdf", "*.docx", "*.md", "*.mdx", "*.rst", "*.txt"):
            files.extend(p.rglob(ext))

    chunks = []
    for f in sorted(files):
        try:
            text = _read_file(f)
        except Exception as e:
            print(f"[files] skipping {f}: {e}", flush=True)
            continue
        for chunk in _chunk(text, str(f)):
            chunks.append(chunk)

    return chunks


def _read_file(path: Path) -> str:
    ext = path.suffix.lower()
    if ext == ".pdf":
        return _read_pdf(path)
    if ext == ".docx":
        return _read_docx(path)
    return path.read_text(encoding="utf-8", errors="replace")


def _read_pdf(path: Path) -> str:
    import fitz  # pymupdf
    with fitz.open(str(path)) as doc:
        return "\n".join(page.get_text() for page in doc)


def _read_docx(path: Path) -> str:
    from docx import Document
    doc = Document(str(path))
    return "\n".join(p.text for p in doc.paragraphs)


def _chunk(text: str, source: str) -> list[dict]:
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        chunk_text = text[start:end].strip()
        if chunk_text:
            chunks.append({"content": chunk_text, "source": source})
        start = end - CHUNK_OVERLAP
    return chunks
