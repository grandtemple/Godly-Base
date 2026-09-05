#!/usr/bin/env python3
"""Create or update a Hero operator (an internal login).

Hashes the password locally with bcrypt before it ever touches the
database or this terminal's scrollback stays clean -- getpass never echoes.

    python scripts/create_operator.py --email you@example.com --name "Joshua Grand"
"""
from __future__ import annotations

import argparse
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from api.auth import get_db_connection, hash_password  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--email", required=True)
    ap.add_argument("--name", required=True, help="display name")
    args = ap.parse_args()

    password = getpass.getpass("Password: ")
    confirm = getpass.getpass("Confirm password: ")
    if password != confirm:
        sys.exit("passwords did not match")
    if len(password) < 12:
        sys.exit("password must be at least 12 characters")

    password_hash = hash_password(password)
    with get_db_connection() as conn, conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO godly.operators (email, password_hash, display_name)
            VALUES (%s, %s, %s)
            ON CONFLICT (email) DO UPDATE
              SET password_hash = EXCLUDED.password_hash,
                  display_name = EXCLUDED.display_name,
                  is_active = true
            """,
            (args.email, password_hash, args.name),
        )
        conn.commit()
    print(f"operator ready: {args.email}")


if __name__ == "__main__":
    main()
