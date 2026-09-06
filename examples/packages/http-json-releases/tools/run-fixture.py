#!/usr/bin/env python3
"""Run the release client against a deterministic local catalog."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import subprocess
import sys
import threading


RELEASES = [
    {"tag_name": "10.47", "prerelease": False, "assets": [{}, {}]},
    {"tag_name": "10.48-RC1", "prerelease": True, "assets": [{}]},
    {"tag_name": "10.46", "prerelease": False, "assets": [{}, {}, {}]},
]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_json(json.dumps(RELEASES, separators=(",", ":")).encode())

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        report = {
            "length": length,
            "type": self.headers.get("Content-Type") or "",
        }
        self.send_json(json.dumps(report, separators=(",", ":")).encode())

    def send_json(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: run-fixture.py RELEASES-EXECUTABLE")
    executable = str(Path(sys.argv[1]).resolve())
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/releases"
        result = subprocess.run(
            [executable, url], check=False, capture_output=True, text=True
        )
        expected = (
            "3 releases\n"
            "  10.47  stable  2 assets\n"
            "  10.48-RC1  preview  1 assets\n"
            "  10.46  stable  3 assets\n"
            "stable: 2; preview: 1; assets: 6\n"
            "posted 35 bytes as application/json\n"
        )
        if result.returncode != 0 or result.stdout != expected:
            sys.stderr.write(result.stderr)
            sys.stderr.write("unexpected output:\n" + result.stdout)
            return 1
        sys.stdout.write(result.stdout)
        return 0
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    raise SystemExit(main())
