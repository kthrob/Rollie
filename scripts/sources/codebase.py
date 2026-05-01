"""
Codebase source: walk a directory, respect .gitignore and .rollieignore,
filter by extension whitelist, chunk by AST (tree-sitter) or fixed size.
"""

import os
from pathlib import Path
import pathspec

DEFAULT_EXTENSIONS = {
    ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".rb",
    ".java", ".swift", ".kt", ".cs", ".cpp", ".c", ".h", ".hpp",
    ".sql", ".md", ".mdx", ".rst", ".txt", ".toml", ".yaml", ".yml",
    ".json", ".sh", ".fish", ".bash",
}

CHUNK_SIZE = 1500
CHUNK_OVERLAP = 200


def ingest(path: str, extensions: set[str] | None = None) -> list[dict]:
    """
    Walk `path`, filter by extension whitelist, respect .gitignore/.rollieignore,
    and return list of {content, source} dicts.
    """
    root = Path(path).resolve()
    allowed_exts = extensions or _load_extension_config() or DEFAULT_EXTENSIONS

    spec = _load_ignore_spec(root)
    chunks = []

    for file_path in sorted(root.rglob("*")):
        if not file_path.is_file():
            continue
        if file_path.suffix.lower() not in allowed_exts:
            continue
        rel = file_path.relative_to(root)
        if spec and spec.match_file(str(rel)):
            continue

        try:
            text = file_path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            print(f"[codebase] skipping {file_path}: {e}", flush=True)
            continue

        file_chunks = _chunk_file(text, str(file_path), file_path.suffix.lower())
        chunks.extend(file_chunks)

    return chunks


def _load_ignore_spec(root: Path) -> pathspec.PathSpec | None:
    patterns = []
    for ignore_file in (".gitignore", ".rollieignore"):
        ig = root / ignore_file
        if ig.exists():
            try:
                patterns.extend(ig.read_text().splitlines())
            except OSError as e:
                print(f"[codebase] skipping {ig}: {e}", flush=True)
    if not patterns:
        return None
    try:
        return pathspec.PathSpec.from_lines("gitwildmatch", patterns)
    except Exception as e:
        print(f"[codebase] malformed ignore file, skipping: {e}", flush=True)
        return None


def _load_extension_config() -> set[str] | None:
    config_file = Path.home() / ".config" / "rollie" / "codebase_extensions"
    if config_file.exists():
        exts = set()
        for line in config_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                exts.add(line if line.startswith(".") else f".{line}")
        return exts or None
    return None


def _chunk_file(text: str, source: str, ext: str) -> list[dict]:
    """Try AST chunking for supported languages; fall back to fixed-size."""
    ast_chunks = _try_ast_chunk(text, source, ext)
    if ast_chunks:
        return ast_chunks
    return _fixed_chunk(text, source)


def _try_ast_chunk(text: str, source: str, ext: str) -> list[dict]:
    """Chunk by top-level functions/classes using tree-sitter."""
    lang_map = {
        ".py": "python", ".ts": "typescript", ".tsx": "tsx",
        ".js": "javascript", ".jsx": "jsx", ".go": "go",
        ".rs": "rust", ".rb": "ruby", ".java": "java",
        ".swift": "swift", ".kt": "kotlin", ".cs": "c_sharp",
        ".cpp": "cpp", ".c": "c",
    }
    lang_name = lang_map.get(ext)
    if not lang_name:
        return []

    try:
        from tree_sitter_languages import get_language, get_parser
        parser = get_parser(lang_name)
        lang = get_language(lang_name)

        tree = parser.parse(text.encode())
        root_node = tree.root_node

        # Collect top-level named declarations
        chunk_types = {
            "function_definition", "class_definition",  # Python
            "function_declaration", "class_declaration", "method_definition",  # JS/TS
            "function_item", "impl_item", "struct_item", "trait_item",  # Rust
            "method_declaration", "class_declaration",  # Java/C#
            "function_definition", "struct_specifier",  # C/C++
        }

        chunks = []
        for child in root_node.children:
            if child.type in chunk_types:
                chunk_text = text[child.start_byte:child.end_byte].strip()
                if len(chunk_text) > 50:  # skip trivial stubs
                    chunks.append({"content": chunk_text, "source": source})

        # If no top-level declarations found, return empty to trigger fallback
        return chunks if chunks else []

    except Exception:
        return []


def _fixed_chunk(text: str, source: str) -> list[dict]:
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        chunk_text = text[start:end].strip()
        if chunk_text:
            chunks.append({"content": chunk_text, "source": source})
        start = end - CHUNK_OVERLAP
    return chunks
