#!/usr/bin/env python3
"""Check database error replies and shutdown while Notes requests are queued."""
import concurrent.futures
import http.client
import importlib.util
import json
import pathlib
import sqlite3
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location(
    "notes_tests", ROOT / "examples/apps/notes/tests/test_notes.py")
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


def pending_create(port, index, sent):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        connection.request("POST", "/api/notes",
                           json.dumps({"title": f"slow-{index}"}),
                           {"Content-Type": "application/json"})
        sent.set()
        response = connection.getresponse()
        body = response.read()
        assert response.status == 201, (response.status, body)
        return json.loads(body)
    finally:
        connection.close()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: test-threaded.py PATH_TO_THREADED_NOTES")
    binary = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="threaded-notes-check-") as temporary:
        directory = pathlib.Path(temporary)
        store = directory / "notes.db"
        with sqlite3.connect(store) as fixture:
            fixture.executescript("""
                CREATE TABLE note (
                  id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
                  body TEXT NOT NULL, tags TEXT NOT NULL,
                  created INTEGER NOT NULL, updated INTEGER NOT NULL);
                CREATE TABLE delay_marker(value INTEGER);
                CREATE TRIGGER reject_note BEFORE INSERT ON note
                WHEN NEW.title = 'reject'
                BEGIN SELECT RAISE(FAIL, 'deliberate check failure'); END;
                CREATE TRIGGER slow_note BEFORE INSERT ON note
                WHEN NEW.title LIKE 'slow-%'
                BEGIN
                  INSERT INTO delay_marker VALUES(1);
                  SELECT count(*) FROM (
                    WITH RECURSIVE count(x) AS (
                      VALUES(1) UNION ALL SELECT x+1 FROM count WHERE x<1000000
                    ) SELECT x FROM count);
                END;
            """)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as clients:
            with notes.running(binary, store, directory) as port:
                result = notes.request(port, "POST", "/api/notes",
                                       {"title": "reject"}, 500)
                assert result == {"error": "internal server error"}, result
                saved = notes.request(port, "POST", "/api/notes",
                                      {"title": "after error"}, 201)
                assert notes.request(port, "GET", "/api/notes/" + saved["id"]) == saved
                sent = [threading.Event() for _ in range(4)]
                pending = [clients.submit(pending_create, port, i, sent[i])
                           for i in range(4)]
                assert all(event.wait(5) for event in sent), "clients did not send"
                deadline = time.monotonic() + 5
                while not pathlib.Path(str(store) + "-journal").exists():
                    assert time.monotonic() < deadline, "no outstanding write"
                    time.sleep(.002)
                # Exit the server context now: SIGTERM must drain its callers.
            created = [future.result(timeout=10) for future in pending]
            assert len({item["id"] for item in created}) == 4
        with sqlite3.connect(store) as fixture:
            assert fixture.execute("SELECT count(*) FROM note").fetchone()[0] == 5
        print("threaded notes: SQL error reply, recovery, and queued shutdown passed")


if __name__ == "__main__":
    main()
