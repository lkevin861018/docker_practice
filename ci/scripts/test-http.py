"""Integration test executed only against ephemeral Docker services in GitHub CI."""
import json
import os
import urllib.request
import uuid

BASE = os.environ.get('BASE_URL', 'http://127.0.0.1:8080')


def req(path, payload=None):
    body = json.dumps(payload).encode('utf-8') if payload is not None else None
    request = urllib.request.Request(
        BASE + path,
        data=body,
        headers={'Content-Type': 'application/json'} if body else {},
        method='POST' if body else 'GET',
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.status, response.read().decode('utf-8')


def main():
    status, body = req('/healthz')
    assert status == 200 and json.loads(body).get('database') == 'connected'
    print('PASS: Flask health + PostgreSQL connection')

    status, page = req('/')
    assert status == 200 and 'Docker' in page
    print('PASS: Nginx homepage')

    name = 'CI-' + uuid.uuid4().hex[:12]
    status, body = req('/api/visits', {'visitor': name})
    created = json.loads(body)
    assert status == 201 and created['visitor'] == name
    print('PASS: PostgreSQL INSERT through API')

    status, body = req('/api/visits')
    rows = json.loads(body)['items']
    assert status == 200 and any(row['id'] == created['id'] for row in rows)
    print('PASS: PostgreSQL SELECT through API')


if __name__ == '__main__':
    main()
