"""
load_raw.py — Step 1 of the pipeline: get Synthea CSVs into Postgres, untouched.

THE BIG IDEA (raw -> staging -> analysis)
-----------------------------------------
Real data teams rarely load files straight into clean, typed tables. They:
  1. RAW:     land the data exactly as received (every column = TEXT).
              Nothing can fail on a bad date or odd number, and you always
              keep an unmodified copy to debug against.
  2. STAGING: clean + cast into proper types in SQL (sql/01_staging.sql).
  3. ANALYSIS: answer business questions against staging (queries/).

This script only does step 1. Being able to explain this layering in an
interview is worth more than the code itself.

Run:  python scripts/load_raw.py
"""

import csv
import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

# The Synthea files we care about. Synthea writes more (payers, devices,
# careplans, ...); add them here later if a question needs them.
TABLES = [
    "patients",
    "encounters",
    "conditions",
    "observations",
    "medications",
    "procedures",
]


def get_connection():
    """Open a Postgres connection using values from .env (or the defaults)."""
    load_dotenv()  # copies .env entries into os.environ
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        user=os.getenv("POSTGRES_USER", "clinical"),
        password=os.getenv("POSTGRES_PASSWORD", "clinical"),
        dbname=os.getenv("POSTGRES_DB", "clinical"),
    )


def load_table(cur, csv_path: Path, table: str) -> int:
    """Create raw.<table> from the CSV header, then bulk-load every row."""

    # 1) Read ONLY the header row to learn the column names.
    #    Deriving columns from the file (instead of hardcoding them) means a
    #    new Synthea version that adds a column won't break the load.
    with open(csv_path, newline="", encoding="utf-8") as f:
        header = next(csv.reader(f))
    columns = [h.strip().lower() for h in header]  # lowercase = no quoting pain in SQL later

    # 2) Recreate the table so re-running the script is safe (idempotent).
    #    Every column is TEXT on purpose — see the docstring at the top.
    cur.execute(f"DROP TABLE IF EXISTS raw.{table}")
    column_defs = ", ".join(f'"{c}" TEXT' for c in columns)
    cur.execute(f"CREATE TABLE raw.{table} ({column_defs})")

    # 3) COPY is Postgres's bulk loader. It streams the whole file in one
    #    command — orders of magnitude faster than one INSERT per row,
    #    which matters because observations.csv can be over a million rows.
    #    In CSV format, empty unquoted fields arrive as NULL.
    with open(csv_path, encoding="utf-8") as f:
        cur.copy_expert(
            f"COPY raw.{table} FROM STDIN WITH (FORMAT csv, HEADER true)", f
        )

    cur.execute(f"SELECT COUNT(*) FROM raw.{table}")
    return cur.fetchone()[0]


def main():
    load_dotenv()
    csv_dir = Path(os.getenv("SYNTHEA_CSV_DIR", "synthea/output/csv"))
    if not csv_dir.exists():
        sys.exit(f"CSV folder not found: {csv_dir} — did you run Synthea yet? (see README)")

    conn = get_connection()
    try:
        # `with conn` wraps everything in ONE transaction: if any table fails,
        # all changes roll back and you never end up with half a load.
        with conn, conn.cursor() as cur:
            cur.execute("CREATE SCHEMA IF NOT EXISTS raw")
            for table in TABLES:
                csv_path = csv_dir / f"{table}.csv"
                if not csv_path.exists():
                    print(f"  skip  {table:<13} (no {csv_path.name})")
                    continue
                rows = load_table(cur, csv_path, table)
                print(f"  load  {table:<13} {rows:>10,} rows")
        print("Raw load complete. Next: run sql/01_staging.sql (see README).")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
