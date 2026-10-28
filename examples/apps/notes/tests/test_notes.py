#!/usr/bin/env python3
"""Exercise the notes HTTP API and persistence through a supplied executable."""

import concurrent.futures
import contextlib
import http.client
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[4]
PUBLIC = ROOT / "examples/apps/notes/public"


def request(port, method, path, body=None, expected=200, raw=False):
    headers = {"Connection": "close"}
    if body is not None:
        headers["Content-Type"] = "application/json"
        if not raw:
            body = json.dumps(body)
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        content = response.read()
        assert response.status == expected, (
            f"{method} {path}: expected {expected}, got "
            f"{response.status}: {content[:500]!r}")
        if path in ("/", "/app.js"):
            return content
        value = json.loads(content)
        if expected >= 400:
            assert isinstance(value.get("error"), str) and value["error"], (
                f"{method} {path}: expected an error reason, got {value!r}")
        return value
    finally:
        connection.close()


@contextlib.contextmanager
def running(binary, store, directory):
    with socket.socket() as available:
        available.bind(("127.0.0.1", 0))
        port = available.getsockname()[1]
    log_path = directory / "server.log"
    with log_path.open("a") as log:
        process = subprocess.Popen([
            str(binary), "--host", "127.0.0.1", "--port", str(port),
            "--workers", "4", "--store", str(store),
            "--public", str(PUBLIC),
        ], cwd=ROOT, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 10
            while True:
                assert process.poll() is None, (
                    f"notes exited during startup ({process.returncode}):\n"
                    f"{log_path.read_text()[-4000:]}")
                try:
                    request(port, "GET", "/api/notes")
                    break
                except (OSError, http.client.HTTPException):
                    assert time.monotonic() < deadline, (
                        f"notes did not become ready:\n"
                        f"{log_path.read_text()[-4000:]}")
                    time.sleep(.02)
            yield port
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise AssertionError("notes did not stop within 10 seconds")
        assert process.returncode == 0, (
            f"notes exited with {process.returncode}:\n"
            f"{log_path.read_text()[-4000:]}")


def note_shape(note, title, body, tags, earliest):
    assert isinstance(note["id"], str) and note["id"].isdigit(), note
    assert note["title"] == title, note
    assert note["body"] == body, note
    assert note["tags"] == tags, note
    for name in ("created", "updated"):
        assert isinstance(note[name], int), note
        assert earliest <= note[name] <= time.time() + 1, note
    assert note["updated"] >= note["created"], note


def check_api(port):
    assert request(port, "GET", "/api/notes") == []
    assert request(port, "GET", "/api/stats") == {
        "notes": 0, "bytes": 0, "tags": {}}
    earliest = int(time.time()) - 1
    first = request(port, "POST", "/api/notes", {
        "title": "Alpha", "body": "caf\u00e9 needle", "tags": ["work", "ideas"]}, 201)
    note_shape(first, "Alpha", "caf\u00e9 needle", ["work", "ideas"], earliest)
    first_path = "/api/notes/" + first["id"]
    assert request(port, "GET", first_path) == first
    second = request(port, "POST", "/api/notes", {"title": "Beta"}, 201)
    note_shape(second, "Beta", "", [], earliest)
    assert second["id"] != first["id"]
    literal = {"title": "<script>alert('note')</script>",
               "body": '<img src=x onerror="alert(1)">', "tags": ["work"]}
    third = request(port, "POST", "/api/notes", literal, 201)
    note_shape(third, literal["title"], literal["body"], ["work"], earliest)

    invalid = [
        {}, {"title": ""}, {"title": 42}, {"title": None},
        {"title": "Invalid", "body": 42},
        {"title": "Invalid", "body": None},
        {"title": "Invalid", "tags": "work"},
        {"title": "Invalid", "tags": None},
        {"title": "Invalid", "tags": [42]},
        {"title": "Invalid", "tags": [None]},
        {"title": "Invalid", "tags": [""]},
        [],
    ]
    for value in invalid:
        request(port, "POST", "/api/notes", value, 422)
    request(port, "POST", "/api/notes", '{"title":', 400, raw=True)
    request(port, "PUT", first_path, {"title": "Invalid", "tags": 42}, 422)
    assert request(port, "GET", first_path) == first

    by_tag = request(port, "GET", "/api/notes?tag=work")
    assert {note["id"] for note in by_tag} == {first["id"], third["id"]}
    query = urllib.parse.urlencode({"tag": "work", "q": "^Alpha$|needle"})
    assert [note["id"] for note in request(
        port, "GET", "/api/notes?" + query)] == [first["id"]]
    assert [note["id"] for note in request(
        port, "GET", "/api/notes?q=needle")] == [first["id"]]
    assert request(port, "GET", "/api/notes?q=not-present") == []
    notes = request(port, "GET", "/api/notes")
    stats = request(port, "GET", "/api/stats")
    assert stats == {
        "notes": 3,
        "bytes": sum(len(note["title"].encode()) + len(note["body"].encode())
                     for note in notes),
        "tags": {"work": 2, "ideas": 1},
    }, stats

    updated = request(port, "PUT", first_path, {
        "title": "Revised", "body": "new body", "tags": ["home"]})
    note_shape(updated, "Revised", "new body", ["home"], earliest)
    assert updated["id"] == first["id"]
    assert updated["created"] == first["created"]
    assert request(port, "GET", first_path) == updated
    assert request(port, "DELETE", "/api/notes/" + second["id"])["deleted"] is True
    missing = "/api/notes/" + second["id"]
    request(port, "GET", missing, expected=404)
    request(port, "PUT", missing, {"title": "Missing"}, 404)
    request(port, "DELETE", missing, expected=404)

    def create(index):
        return request(port, "POST", "/api/notes", {
            "title": f"Concurrent {index}", "body": str(index),
            "tags": ["parallel"]}, 201)

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        created = list(pool.map(create, range(16)))
    assert len({note["id"] for note in created}) == 16
    assert not {note["id"] for note in created} & {first["id"], third["id"]}
    stats = request(port, "GET", "/api/stats")
    assert stats["notes"] == 18, stats
    assert stats["tags"] == {"home": 1, "work": 1, "parallel": 16}, stats
    ordinary = {"title": "Ordinary note", "body": "x" * 70000,
                "tags": ["forbidden"]}
    accepted = request(port, "POST", "/api/notes", ordinary, 201)
    note_shape(accepted, ordinary["title"], ordinary["body"],
               ordinary["tags"], earliest)
    assert request(port, "GET", "/api/notes/" + accepted["id"]) == accepted
    for route, filename in (("/", "index.html"), ("/app.js", "app.js")):
        assert request(port, "GET", route) == (PUBLIC / filename).read_bytes()
    return request(port, "GET", "/api/notes")


def check_startup(binary, directory):
    store = directory / "unused.db"
    help_result = subprocess.run([str(binary), "--help"], cwd=ROOT,
                                 capture_output=True, text=True, timeout=5)
    assert help_result.returncode == 0, help_result.stderr
    assert "--store" in help_result.stdout and "--workers" in help_result.stdout
    for arguments in (["--bad-option"], ["--port", "-1"],
                      ["--port", "65536"], ["--port", "abc"],
                      ["--workers", "0"], ["--workers", "1025"],
                      ["--workers", "abc"]):
        result = subprocess.run([str(binary), "--store", str(store), *arguments],
                                cwd=ROOT, capture_output=True, text=True,
                                timeout=5)
        assert result.returncode == 2, (
            f"{arguments}: expected usage failure, got {result.returncode}: "
            f"{result.stderr}")
        assert result.stderr.strip(), f"{arguments}: missing error message"
    assert not store.exists(), "invalid arguments created a database"

    old_store = directory / "old-notes.json"
    original = b'{"1":{"id":"1","title":"Old note","body":"keep me","tags":[]}}\n'
    old_store.write_bytes(original)
    result = subprocess.run([str(binary), "--store", str(old_store), "--port", "0"],
                            cwd=ROOT, capture_output=True, text=True, timeout=5)
    assert result.returncode > 0, (
        f"JSON store must fail cleanly: {result.returncode}: {result.stderr}")
    assert "notes:" in result.stderr, "missing incompatible-store diagnostic"
    assert old_store.read_bytes() == original, "JSON store bytes changed"


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_notes.py PATH_TO_NOTES_EXECUTABLE")
    binary = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="x2c-notes-tests-") as temporary:
        directory = pathlib.Path(temporary)
        check_startup(binary, directory)
        store = directory / "notes.data"
        with running(binary, store, directory) as port:
            expected = check_api(port)
        assert store.is_file(), "notes did not persist a store file"
        with running(binary, store, directory) as port:
            actual = request(port, "GET", "/api/notes")
            assert {note["id"]: note for note in actual} == {
                note["id"]: note for note in expected}, "notes changed after restart"
            saved = request(port, "POST", "/api/notes", {"title": "After restart"}, 201)
            assert saved["id"] not in {note["id"] for note in expected}
    print("notes: API, concurrency, restart, CLI, and store compatibility passed")


if __name__ == "__main__":
    main()
