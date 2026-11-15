"""A tiny web app for day 21: shows where it runs and what configuration reached it.

It never prints the secret itself, only how long it is.
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(
            {
                "app": "day21-app",
                "version": os.environ.get("APP_VERSION", "unknown"),
                "pod": socket.gethostname(),
                "greeting": os.environ.get("APP_GREETING", "(not set)"),
                "db_user": os.environ.get("DB_USER", "(not set)"),
                "db_password_length": len(os.environ.get("DB_PASSWORD", "")),
            },
            indent=2,
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # keep the pod logs short
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
