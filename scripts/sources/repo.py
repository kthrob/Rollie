"""
Repo source: shallow-clone a GitHub repo to a temp dir and run codebase ingestion.
Only code and doc files are ingested (no lock files, build artifacts, etc.).
"""

import subprocess
import tempfile
from pathlib import Path
from . import codebase


def ingest(github_url: str) -> list[dict]:
    """Shallow-clone `github_url` and return codebase chunks."""
    with tempfile.TemporaryDirectory(prefix="rollie-repo-") as tmpdir:
        print(f"[repo] Cloning {github_url} → {tmpdir}", flush=True)
        result = subprocess.run(
            ["git", "clone", "--depth=1", "--quiet", github_url, tmpdir],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"[repo] git clone failed: {result.stderr.strip()}", flush=True)
            return []

        print(f"[repo] Ingesting cloned repo...", flush=True)
        chunks = codebase.ingest(tmpdir)
        return chunks
