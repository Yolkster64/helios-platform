from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent


class Handler(BaseHTTPRequestHandler):
    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path in ("/health", "/api/status"):
            self.send_json({
                "status": "ready",
                "environment": os.getenv("HELIOS_ENVIRONMENT", "local"),
                "hermes": {"mode": os.getenv("HERMES_MODE", "adapter"), "status": "configured"},
                "xcore": {"trainingEnabled": os.getenv("XCORE_TRAINING_ENABLED", "false").lower() == "true"},
                "controlCenter": "monado",
            })
            return
        path = ROOT / "wwwroot" / ("index.html" if self.path == "/" else self.path.lstrip("/"))
        if path.is_file() and ROOT / "wwwroot" in path.parents:
            body = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

