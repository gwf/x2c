#!/usr/bin/env python3
"""Run one executable against a deterministic package-local HTTP fixture."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import json
import subprocess
import sys
import threading
import time


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, *args):
        super().__init__(*args)
        self.batch_lock = threading.Lock()
        self.batch_ready = threading.Event()
        self.batch_active = 0
        self.batch_peak = 0
        self.batch_finished = []

    def handle_error(self, request, client_address):
        pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if urlparse(self.path).path == "/echo":
            self.echo("GET")
            return
        answer = self.resolve()
        if answer is None:
            return
        self.send_fixed(*answer)

    def do_HEAD(self):
        answer = self.resolve()
        if answer is None:
            return
        status, reason, headers, body = answer
        self.send_fixed(status, reason, headers, body, omit_body=True)

    def do_POST(self):
        self.echo("POST")

    def do_PUT(self):
        self.echo("PUT")

    def do_DELETE(self):
        self.echo("DELETE")

    def echo(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        report = {
            "method": method,
            "type": self.headers.get("Content-Type") or "",
            "length": length,
            "content_length": self.headers.get("Content-Length"),
            "body": body.decode("utf-8", "replace"),
        }
        self.send_fixed(
            200,
            "OK",
            [("Content-Type", "application/json")],
            json.dumps(report, sort_keys=True).encode(),
        )

    def resolve(self):
        """The (status, reason, headers, body) a GET or a HEAD receives."""
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/batch/reset":
            with self.server.batch_lock:
                self.server.batch_peak = 0
                self.server.batch_finished.clear()
                self.server.batch_ready.clear()
            return (200, "OK", [], b"reset")
        if path == "/batch/stats":
            with self.server.batch_lock:
                body = (str(self.server.batch_peak) + " " +
                        ",".join(self.server.batch_finished)).encode()
            return (200, "OK", [], body)
        if path == "/batch/delay":
            query = parse_qs(parsed.query)
            name = query.get("name", ["done"])[0]
            barrier = int(query.get("barrier", ["0"])[0])
            with self.server.batch_lock:
                self.server.batch_active += 1
                self.server.batch_peak = max(
                    self.server.batch_peak, self.server.batch_active)
                if barrier and self.server.batch_active >= barrier:
                    self.server.batch_ready.set()
            try:
                if barrier:
                    self.server.batch_ready.wait(2)
                time.sleep(int(query.get("ms", ["0"])[0]) / 1000)
                with self.server.batch_lock:
                    self.server.batch_finished.append(name)
                return (200, "OK", [], name.encode())
            finally:
                with self.server.batch_lock:
                    self.server.batch_active -= 1
        pages = {
            "/guide": b"<html><title>x2c Language Guide</title></html>",
            "/reference": b"<html><title>x2c Reference</title></html>",
            "/source": b"<html><title>x2c Source</title></html>",
        }
        if path in pages:
            return (
                200,
                "OK",
                [("Content-Type", "text/html")],
                pages[path],
            )
        if path == "/close":
            self.close_connection = True
            return None
        if path == "/redirect":
            return (
                302,
                "Found",
                [("Location", "/binary"), ("X-Hop", "redirect")],
                b"",
            )
        if path == "/binary":
            return (
                200,
                "OK",
                [
                    ("Content-Type", "application/octet-stream"),
                    ("X-Trace", "alpha"),
                    ("X-Trace", "beta"),
                    ("X-Empty", ""),
                ],
                b"abc\0def",
            )
        if path == "/empty":
            return (204, "No Content", [("X-Empty", "")], b"")
        if path == "/large":
            return (
                200,
                "OK",
                [("Content-Type", "application/octet-stream")],
                b"x" * 64,
            )
        if path == "/download":
            return (
                200,
                "OK",
                [("Content-Type", "application/octet-stream")],
                b"".join(b"packet %04d\n" % n for n in range(256)),
            )
        if path == "/secret":
            expected = "Basic dXNlcjpzM2NyZXQ="
            if self.headers.get("Authorization") != expected:
                return (
                    401,
                    "Unauthorized",
                    [("WWW-Authenticate", 'Basic realm="fixture"')],
                    b"denied",
                )
            return (
                200,
                "OK",
                [("Content-Type", "text/plain")],
                b"release-7 signing key",
            )
        if path == "/search":
            query = parse_qs(parsed.query, keep_blank_values=True)
            term = query.get("q", [""])[0]
            return (
                200,
                "OK",
                [("Content-Type", "text/plain")],
                f"searched for {term}".encode(),
            )
        if path == "/headers-large":
            value = "x" * 90000
            return (
                200,
                "OK",
                [
                    ("X-Large-One", value),
                    ("X-Large-Two", value),
                    ("X-Large-Three", value),
                ],
                b"",
            )
        if path == "/trailers":
            self.send_response_only(200, "OK")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Trailer", "X-Trailer")
            self.end_headers()
            self.wfile.write(
                b"5\r\nhello\r\n0\r\nX-Trailer: finished\r\n\r\n"
            )
            return None
        if path == "/compat":
            matched = (
                self.headers.get("User-Agent") == "x2c-compat-test/1"
                and self.headers.get("Accept") == "application/json"
            )
            return (
                200 if matched else 400,
                "OK" if matched else "Bad Request",
                [("X-Compat", "matched" if matched else "mismatch")],
                b"matched" if matched else b"mismatch",
            )
        if path == "/ok":
            return (
                200,
                "OK",
                [
                    ("Content-Type", "text/plain"),
                    ("X-Trace", "alpha"),
                    ("X-Trace", "beta"),
                    ("X-Empty", ""),
                ],
                b"hello",
            )
        return (
            404,
            "Not Found",
            [("Content-Type", "text/plain")],
            b"not found",
        )

    def send_fixed(self, status, reason, headers, body, omit_body=False):
        self.send_response_only(status, reason)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and not omit_body:
            self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: run-fixture.py EXECUTABLE")
    executable = str(Path(sys.argv[1]).resolve())
    server = FixtureServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base = f"http://127.0.0.1:{server.server_port}"
        result = subprocess.run(
            [executable, base], check=False, capture_output=True
        )
        sys.stdout.buffer.write(
            result.stdout.replace(base.encode(), b"http://fixture")
        )
        sys.stderr.buffer.write(
            result.stderr.replace(base.encode(), b"http://fixture")
        )
        return result.returncode
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    raise SystemExit(main())
