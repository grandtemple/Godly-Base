#!/usr/bin/env python3
"""Extract any Godly Base table to CSV or JSON on disk.

The OS Data module shows the same rows and copies them to the clipboard;
this writes real files. It reads live Postgres when DATABASE_URL is set, and
falls back to the committed seed (db/seed.json) otherwise.

    python scripts/extract.py --list
    python scripts/extract.py --table deals --format csv --out exports/
    python scripts/extract.py --table contacts --where "email_status='verified'"
    python scripts/extract.py --all --format json --out exports/
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "db" / "seed.json"

# seed key -> live table name. Keys the seed carries that are not tables are skipped.
TABLES = {
    "front_office": "front_office_capabilities",
    "customers": "customers",
    "jobs": "jobs",
    "customer_interactions": "customer_interactions",
    "customer_invoices": "customer_invoices",
    "reviews": "reviews",
    "payment_accounts": "payment_accounts",
    "payments": "payments",
    "dunning_attempts": "dunning_attempts",
    "price_book": "price_book",
    "quotes": "quotes",
    "retainers": "retainers",
    "invoices": "invoices",
    "deployments": "deployments",
    "accounts": "accounts",
    "contacts": "contacts",
    "deals": "deals",
    "partners": "partners",
    "campaigns": "campaigns",
    "content": "content_items",
    "agents": "agents",
    "agent_runs": "agent_runs",
    "api_keys": "integrations",
    "sources": "sources",
    "brain": "brain_map",
    "funnel": "funnel_snapshots",
}
IDENT = re.compile(r"^[a-z_][a-z0-9_]*$")


def jsonable(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def from_seed(key: str) -> list[dict]:
    if not SEED.exists():
        sys.exit(f"no seed at {SEED} and no DATABASE_URL set")
    data = json.loads(SEED.read_text())
    if key not in data:
        sys.exit(f"unknown table '{key}'. try --list")
    return data[key]


def from_postgres(key: str, where: str | None, limit: int | None) -> list[dict]:
    try:
        import psycopg
    except ImportError:
        sys.exit("psycopg is not installed — run `pip install 'psycopg[binary]'` or drop DATABASE_URL to use the seed")
    table = TABLES[key]
    if not IDENT.match(table):
        sys.exit(f"refusing unsafe table name: {table}")
    sql = f"SELECT * FROM godly.{table}"
    if where:
        sql += f" WHERE {where}"          # operator-supplied; this is a local admin tool
    if limit:
        sql += f" LIMIT {int(limit)}"
    TENANT_SCOPED = {"customers", "jobs", "customer_interactions", "customer_invoices", "reviews"}
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn, conn.cursor() as cur:
        if table in TENANT_SCOPED and os.environ.get("DEPLOYMENT_ID"):
            # RLS fails closed: without a tenant these tables return nothing at all
            cur.execute("SET app.deployment_id = %s", (os.environ["DEPLOYMENT_ID"],))
        cur.execute(sql)
        cols = [c.name for c in cur.description]
        return [{c: jsonable(v) for c, v in zip(cols, row)} for row in cur.fetchall()]


def fetch(key: str, where: str | None, limit: int | None) -> list[dict]:
    if os.environ.get("DATABASE_URL"):
        return from_postgres(key, where, limit)
    rows = from_seed(key)
    if limit:
        rows = rows[:limit]
    if where:
        print(f"note: --where is ignored in seed mode ({key})", file=sys.stderr)
    return rows


def to_csv(rows: list[dict]) -> str:
    if not rows:
        return ""
    cols, seen = [], set()
    for row in rows:                       # union of keys, first-seen order
        for k in row:
            if k not in seen:
                seen.add(k)
                cols.append(k)
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=cols, extrasaction="ignore")
    writer.writeheader()
    for row in rows:
        writer.writerow({k: ("" if row.get(k) is None else json.dumps(row[k], default=str)
                             if isinstance(row.get(k), (dict, list)) else row.get(k))
                         for k in cols})
    return buf.getvalue()


def write(key: str, rows: list[dict], fmt: str, out: Path | None) -> None:
    body = to_csv(rows) if fmt == "csv" else json.dumps(rows, indent=2, default=str)
    if out is None:
        sys.stdout.write(body if body.endswith("\n") else body + "\n")
        return
    out.mkdir(parents=True, exist_ok=True)
    stamp = date.today().isoformat()
    path = out / f"{key}-{stamp}.{fmt}"
    path.write_text(body)
    print(f"{len(rows):>5} rows → {path}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Extract Godly Base data points.")
    ap.add_argument("--table", choices=sorted(TABLES))
    ap.add_argument("--all", action="store_true", help="every table")
    ap.add_argument("--list", action="store_true", help="show tables and row counts")
    ap.add_argument("--format", choices=["csv", "json"], default="csv")
    ap.add_argument("--where", help="SQL predicate (live database only)")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--out", type=Path, help="directory to write into; omit to print")
    args = ap.parse_args()

    source = "postgres" if os.environ.get("DATABASE_URL") else "seed"

    if args.list:
        print(f"source: {source}")
        for key in sorted(TABLES):
            try:
                print(f"  {key:<12} {len(fetch(key, None, None)):>5} rows  → godly.{TABLES[key]}")
            except SystemExit:
                print(f"  {key:<12}     ?  → godly.{TABLES[key]}")
        return

    if args.all:
        for key in sorted(TABLES):
            write(key, fetch(key, args.where, args.limit), args.format, args.out or Path("exports"))
        return

    if not args.table:
        ap.error("pass --table, --all, or --list")
    write(args.table, fetch(args.table, args.where, args.limit), args.format, args.out)


if __name__ == "__main__":
    main()
