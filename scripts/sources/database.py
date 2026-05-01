"""
Database source: extract schema and sample rows from SQLite or PostgreSQL.
Returns text chunks describing tables, columns, types, and example data.
"""

SAMPLE_ROWS = 5
CHUNK_SIZE = 1500


def ingest(connection_string: str) -> list[dict]:
    """
    Connect to a SQLite or PostgreSQL database, reflect its schema,
    sample rows, and return list of {content, source} dicts.
    """
    from sqlalchemy import create_engine, inspect

    engine = create_engine(connection_string)
    inspector = inspect(engine)
    table_names = inspector.get_table_names()

    chunks = []
    for table in table_names:
        description = _describe_table(inspector, table)
        samples = _sample_rows(engine, table)
        content = f"{description}\n\nSample rows:\n{samples}"
        chunks.extend(_split(content, f"db:{connection_string}#{table}"))

    return chunks


def _describe_table(inspector, table: str) -> str:
    columns = inspector.get_columns(table)
    pk_constraint = inspector.get_pk_constraint(table)
    pks = set(pk_constraint.get("constrained_columns", []))
    fks = inspector.get_foreign_keys(table)
    indexes = inspector.get_indexes(table)

    col_lines = []
    for col in columns:
        parts = [col["name"], str(col["type"])]
        if col["name"] in pks:
            parts.append("PRIMARY KEY")
        if not col.get("nullable", True):
            parts.append("NOT NULL")
        col_lines.append("  " + ", ".join(parts))

    fk_lines = []
    for fk in fks:
        ref_table = fk["referred_table"]
        col_pairs = ", ".join(
            f"{c} → {r}"
            for c, r in zip(fk["constrained_columns"], fk["referred_columns"])
        )
        fk_lines.append(f"  FK: {col_pairs} references {ref_table}")

    idx_lines = []
    for idx in indexes:
        cols = ", ".join(idx["column_names"])
        unique = " (unique)" if idx.get("unique") else ""
        idx_lines.append(f"  Index {idx['name']}{unique}: {cols}")

    parts = [f"Table: {table}", "Columns:"] + col_lines
    if fk_lines:
        parts += ["Foreign keys:"] + fk_lines
    if idx_lines:
        parts += ["Indexes:"] + idx_lines

    return "\n".join(parts)


def _sample_rows(engine, table: str) -> str:
    from sqlalchemy import text, quoted_name
    try:
        with engine.connect() as conn:
            safe_table = quoted_name(table, quote=True)
            result = conn.execute(text(f"SELECT * FROM {safe_table} LIMIT {SAMPLE_ROWS}"))
            rows = result.fetchall()
            if not rows:
                return "(no rows)"
            keys = list(result.keys())
            lines = ["  " + " | ".join(str(k) for k in keys)]
            for row in rows:
                lines.append("  " + " | ".join(str(v) for v in row))
            return "\n".join(lines)
    except Exception as e:
        print(f"[database] could not sample rows from {table}: {e}", flush=True)
        return "(no sample data)"


def _split(text: str, source: str) -> list[dict]:
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        chunk = text[start:end].strip()
        if chunk:
            chunks.append({"content": chunk, "source": source})
        start = end - 200
    return chunks
