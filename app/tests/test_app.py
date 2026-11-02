"""Unit tests for the current Flask app, no live database required."""
import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch
import psycopg
from app import app


class ApiTests(unittest.TestCase):
    def setUp(self):
        app.testing = True
        self.client = app.test_client()

    def test_homepage(self):
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        self.assertIn(b'Docker', response.data)

    def test_reject_missing_visitor(self):
        response = self.client.post('/api/visits', json={'other': 'value'})
        self.assertEqual(response.status_code, 400)

    def test_reject_empty_visitor(self):
        response = self.client.post('/api/visits', json={'visitor': '   '})
        self.assertEqual(response.status_code, 400)

    def test_reject_long_visitor(self):
        response = self.client.post('/api/visits', json={'visitor': 'x' * 81})
        self.assertEqual(response.status_code, 400)

    @patch('app.connect_db')
    def test_db_query_parameterized(self, connect_db):
        conn = MagicMock()
        cursor = MagicMock()
        connect_db.return_value.__enter__.return_value = conn
        conn.cursor.return_value.__enter__.return_value = cursor
        cursor.fetchone.return_value = (12, 'CI', datetime(2026, 1, 1, tzinfo=timezone.utc))
        response = self.client.post('/api/visits', json={'visitor': 'CI'})
        self.assertEqual(response.status_code, 201)
        sql, values = cursor.execute.call_args.args
        self.assertIn('%s', sql)
        self.assertEqual(values, ('CI',))

    @patch('app.connect_db', side_effect=psycopg.OperationalError('offline'))
    def test_health_reports_db_failure(self, _connect_db):
        response = self.client.get('/healthz')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json['status'], 'unavailable')


if __name__ == '__main__':
    unittest.main()
