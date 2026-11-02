"""Flask + PostgreSQL demo. For local learning, not a public production app."""
import os
import time

import psycopg
from flask import Flask, jsonify, render_template, request, g
from prometheus_client import Counter, Histogram, make_wsgi_app
from werkzeug.middleware.dispatcher import DispatcherMiddleware

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024  # Simple JSON payload limit

# Lab runs one Gunicorn worker to keep Prometheus in-process metrics coherent.
REQUEST_COUNT = Counter(
    "flask_http_requests_total", "Total HTTP requests", ["method", "route", "status"]
)
REQUEST_LATENCY = Histogram(
    "flask_http_request_duration_seconds", "HTTP request duration in seconds",
    ["method", "route"],
    buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10),
)

@app.before_request
def metrics_before():
    g.started_at = time.perf_counter()

@app.after_request
def metrics_after(response):
    route = request.url_rule.rule if request.url_rule else "unmatched"
    # Don't use full URL paths as labels (high cardinality risk).
    method = request.method
    REQUEST_COUNT.labels(method, route, str(response.status_code)).inc()
    REQUEST_LATENCY.labels(method, route).observe(time.perf_counter() - g.started_at)
    return response

# /metrics is internal to the Flask container network; Nginx blocks external access.
app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {"/metrics": make_wsgi_app()})


def get_db_password():
    """Prefer Compose-mounted secret file, fall back to existing lab environment."""
    password_file = os.environ.get("DB_PASSWORD_FILE")
    if password_file:
        with open(password_file, "r", encoding="utf-8") as handle:
            return handle.read().rstrip("\r\n")
    return os.environ["DB_PASSWORD"]


def connect_db():
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "db"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=get_db_password(),
        connect_timeout=5,
    )


def format_visit(row):
    visit_id, visitor, created_at = row
    return {"id": visit_id, "visitor": visitor, "created_at": created_at.isoformat()}


@app.get("/")
def home():
    return render_template("index.html")


@app.get("/healthz")
def healthz():
    try:
        with connect_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
    except psycopg.Error:
        app.logger.exception("Database health check failed")
        return jsonify(status="unavailable"), 503
    return jsonify(status="ok", app="flask", database="connected")


@app.get("/api/visits")
def get_visits():
    with connect_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, visitor, created_at "
                "FROM visits ORDER BY id DESC LIMIT 20"
            )
            rows = cur.fetchall()
    return jsonify(items=[format_visit(row) for row in rows])


@app.post("/api/visits")
def create_visit():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict) or not isinstance(payload.get("visitor"), str):
        return jsonify(error="JSON must contain a visitor string"), 400

    visitor = payload["visitor"].strip()
    if not (1 <= len(visitor) <= 80):
        return jsonify(error="visitor must contain 1 to 80 characters"), 400

    with connect_db() as conn:
        with conn.cursor() as cur:
            # Parameterized SQL; never concatenate user input into the query.
            cur.execute(
                "INSERT INTO visits (visitor) VALUES (%s) "
                "RETURNING id, visitor, created_at",
                (visitor,),
            )
            row = cur.fetchone()
    return jsonify(format_visit(row)), 201
