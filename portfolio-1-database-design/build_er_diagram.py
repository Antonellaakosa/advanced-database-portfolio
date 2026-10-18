#!/usr/bin/env python3
"""
Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 1
Builds the ER diagram directly from the live PostgreSQL schema, so the
picture can never disagree with the database.

Usage (needs Graphviz: sudo apt-get install -y graphviz):
    python3 build_er_diagram.py
Environment variables PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD are
read by psql in the usual way.
Output: er_diagram.dot, er_diagram.png, er_diagram.svg
"""
import subprocess
import sys
from collections import defaultdict


def query(sql: str):
    """Run a SQL query through psql and return rows as lists of strings."""
    out = subprocess.run(
        ["psql", "-At", "-F", "|", "-c", sql],
        capture_output=True, text=True, check=True,
    ).stdout
    return [line.split("|") for line in out.splitlines() if line]


COLUMNS = query("""
    SELECT table_name, column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN (SELECT table_name FROM information_schema.tables
                         WHERE table_schema = 'public' AND table_type = 'BASE TABLE')
    ORDER BY table_name, ordinal_position""")

PKS = {(t, c) for t, c in query("""
    SELECT tc.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON kcu.constraint_name = tc.constraint_name AND kcu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = 'public'""")}

FKS = query("""
    SELECT kcu.table_name, kcu.column_name, ccu.table_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON kcu.constraint_name = tc.constraint_name AND kcu.table_schema = tc.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public'""")
FKS = [tuple(r) for r in FKS]
FK_COLS = {(t, c) for t, c, _ in FKS}

SHORT = {"character varying": "varchar", "timestamp with time zone": "timestamptz",
         "character": "char", "integer": "int", "smallint": "smallint"}

tables = defaultdict(list)
for table, col, dtype, nullable in COLUMNS:
    tables[table].append((col, SHORT.get(dtype, dtype), nullable))

lines = [
    "digraph UPLN {",
    '  graph [rankdir=LR, nodesep=0.35, ranksep=1.2, fontname="Helvetica", '
    'label="Unity Public Library Network - Entity Relationship Diagram (generated from PostgreSQL)", '
    "labelloc=t, fontsize=20];",
    '  node  [shape=plain, fontname="Helvetica", fontsize=10];',
    '  edge  [dir=both, arrowtail=tee, arrowhead=crow, color="#555555", penwidth=1.1];',
]
for table, cols in sorted(tables.items()):
    rows = [f'<TR><TD COLSPAN="3" BGCOLOR="#1f4e79"><FONT COLOR="white"><B>{table}</B></FONT></TD></TR>']
    for col, dtype, nullable in cols:
        key = "PK" if (table, col) in PKS else ("FK" if (table, col) in FK_COLS else "")
        if (table, col) in PKS and (table, col) in FK_COLS:
            key = "PK,FK"
        bold = f"<B>{col}</B>" if key.startswith("PK") else col
        shade = ' BGCOLOR="#fff2cc"' if key.startswith("PK") else (' BGCOLOR="#e2efda"' if key == "FK" else "")
        rows.append(
            f'<TR><TD ALIGN="LEFT"{shade}>{key}</TD><TD ALIGN="LEFT"{shade}>{bold}</TD>'
            f'<TD ALIGN="LEFT"{shade}><FONT COLOR="#666666">{dtype}</FONT></TD></TR>')
    lines.append(f'  {table} [label=<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" '
                 f'CELLPADDING="3" BGCOLOR="white">{"".join(rows)}</TABLE>>];')

for child, col, parent in sorted(set(FKS)):
    lines.append(f'  {parent} -> {child} [tooltip="{child}.{col} references {parent}"];')
lines.append("}")

with open("er_diagram.dot", "w") as handle:
    handle.write("\n".join(lines))

for fmt in ("png", "svg"):
    cmd = ["dot", f"-T{fmt}", "-Gdpi=150", "er_diagram.dot", "-o", f"er_diagram.{fmt}"]
    if subprocess.run(cmd).returncode != 0:
        sys.exit("Graphviz 'dot' failed. Is Graphviz installed?")
print(f"Wrote er_diagram.dot / .png / .svg  ({len(tables)} tables, {len(set(FKS))} foreign-key links)")
