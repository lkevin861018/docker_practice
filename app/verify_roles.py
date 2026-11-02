"""Verify that the app can write, readers cannot write, and app cannot delete."""
import os
import psycopg


def connect(prefix):
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "db"),
        dbname=os.environ["DB_NAME"],
        user=os.environ[f"{prefix}_DB_USER"],
        password=os.environ[f"{prefix}_DB_PASSWORD"],
        connect_timeout=8,
    )


with connect("APP") as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.visits")
        print("PASS: Flask can SELECT; row count:", cur.fetchone()[0])
        cur.execute("INSERT INTO public.visits (visitor) VALUES ('role-check-temporary') RETURNING id")
        print("PASS: Flask can INSERT; temporary id:", cur.fetchone()[0])
    conn.rollback()  # Never leave test rows behind.

with connect("APP") as conn:
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM public.visits WHERE FALSE")
    except psycopg.errors.InsufficientPrivilege:
        print("PASS: Flask cannot DELETE")
        conn.rollback()
    else:
        raise SystemExit("FAIL: Flask unexpectedly has DELETE privilege")

with connect("REPORT") as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.visits")
        print("PASS: report_reader can SELECT; row count:", cur.fetchone()[0])

with connect("REPORT") as conn:
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO public.visits (visitor) VALUES ('should-not-write')")
    except psycopg.errors.InsufficientPrivilege:
        print("PASS: report_reader cannot INSERT")
        conn.rollback()
    else:
        raise SystemExit("FAIL: report_reader unexpectedly has INSERT privilege")

print("All database permission checks passed.")
