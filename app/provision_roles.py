"""Idempotent PostgreSQL grants for the existing lab database.
Run only with the Docker Compose db-setup maintenance service.
"""
import os
import re

import psycopg
from psycopg import sql


def required(name):
    value = os.environ.get(name, "")
    if not value or value.startswith("REPLACE_ME_"):
        raise SystemExit(f"Set a non-placeholder value for {name} in .env")
    return value


admin_user = required("DB_ADMIN_USER")
admin_pw = required("DB_ADMIN_PASSWORD")
app_user = required("APP_DB_USER")
app_pw = required("APP_DB_PASSWORD")
reader_user = required("REPORT_DB_USER")
reader_pw = required("REPORT_DB_PASSWORD")
dbname = required("DB_NAME")
metrics_user = required("METRICS_DB_USER")
metrics_pw = required("METRICS_DB_PASSWORD")

for role in (app_user, reader_user):
    if not re.fullmatch(r"[a-z_][a-z0-9_]{0,62}", role):
        raise SystemExit(f"Invalid PostgreSQL role name: {role!r}")
    if role.startswith("pg_") or role in {"postgres", admin_user}:
        raise SystemExit("Refusing to reuse PostgreSQL administrator or reserved role")
if metrics_user in (app_user, reader_user, admin_user) or metrics_user.startswith("pg_") or not re.fullmatch(r"[a-z_][a-z0-9_]{0,62}", metrics_user):
    raise SystemExit("Metrics role must be a separate, valid, non-reserved PostgreSQL role")
if app_user == reader_user:
    raise SystemExit("Flask and report roles must be different")

with psycopg.connect(
    host=os.environ.get("DB_HOST", "db"),
    port=int(os.environ.get("DB_PORT", "5432")),
    dbname=dbname,
    user=admin_user,
    password=admin_pw,
    autocommit=True,
    connect_timeout=8,
) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT to_regclass('public.visits'), to_regclass('public.visits_id_seq')")
        table, sequence = cur.fetchone()
        if table is None or sequence is None:
            raise SystemExit("visits and visits_id_seq not found. Initialize the original database first.")

        for name, password in ((app_user, app_pw), (reader_user, reader_pw)):
            cur.execute(
                "SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication "
                "FROM pg_roles WHERE rolname = %s", (name,)
            )
            status = cur.fetchone()
            if status is not None and any(status):
                raise SystemExit(f"Existing role {name!r} has elevated privileges. Refusing to alter it.")
            if status is not None:
                cur.execute(
                    "SELECT 1 FROM pg_auth_members m "
                    "JOIN pg_roles r ON r.oid = m.member "
                    "WHERE r.rolname = %s LIMIT 1", (name,)
                )
                if cur.fetchone() is not None:
                    raise SystemExit(f"Existing role {name!r} has inherited memberships. Refusing.")
            if status is None:
                cur.execute(sql.SQL("CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE "
                                    "NOREPLICATION PASSWORD {}").format(
                    sql.Identifier(name), sql.Literal(password)))
                print(f"Created role: {name}")
            else:
                cur.execute(sql.SQL("ALTER ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE "
                                    "NOREPLICATION PASSWORD {}").format(
                    sql.Identifier(name), sql.Literal(password)))
                print(f"Updated role password: {name}")

        both = sql.SQL("{}, {}").format(sql.Identifier(app_user), sql.Identifier(reader_user))
        # Restrict access to the exact demo table and sequence, not every public schema table.
        cur.execute(sql.SQL("REVOKE ALL ON TABLE public.visits FROM {}").format(both))
        cur.execute(sql.SQL("REVOKE ALL ON SEQUENCE public.visits_id_seq FROM {}").format(both))
        cur.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(
            sql.Identifier(dbname), both))
        cur.execute(sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(both))
        cur.execute(sql.SQL("GRANT SELECT, INSERT ON TABLE public.visits TO {}").format(
            sql.Identifier(app_user)))
        cur.execute(sql.SQL("GRANT USAGE ON SEQUENCE public.visits_id_seq TO {}").format(
            sql.Identifier(app_user)))
        cur.execute(sql.SQL("GRANT SELECT ON TABLE public.visits TO {}").format(
            sql.Identifier(reader_user)))


        # PostgreSQL predefined pg_monitor role allows monitoring views without
        # giving the exporter SUPERUSER or table write access.
        cur.execute("SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication FROM pg_roles WHERE rolname=%s", (metrics_user,))
        mstatus = cur.fetchone()
        if mstatus is not None and any(mstatus):
            raise SystemExit("Refusing elevated existing monitoring role")
        if mstatus is not None:
            cur.execute("SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid "
                        "JOIN pg_roles u ON u.oid=m.member WHERE u.rolname=%s", (metrics_user,))
            memberships = {row[0] for row in cur.fetchall()}
            if not memberships.issubset({"pg_monitor"}):
                raise SystemExit("Existing monitoring role has unexpected group memberships")
        cur.execute(sql.SQL("{} ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD {}").format(
            sql.SQL("ALTER") if mstatus is not None else sql.SQL("CREATE"),
            sql.Identifier(metrics_user), sql.Literal(metrics_pw)))
        cur.execute(sql.SQL("GRANT pg_monitor TO {}").format(sql.Identifier(metrics_user)))
        cur.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(sql.Identifier(dbname), sql.Identifier(metrics_user)))

print("Roles provisioned. Flask: SELECT/INSERT + sequence USAGE; report: SELECT only; metrics: pg_monitor.")
