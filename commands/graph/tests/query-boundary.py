#!/usr/bin/env python3
"""Reject malformed queries even when the snapshot has no matching code."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    tool = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="x2c-query-boundary-") as temporary:
        root = Path(temporary)
        source = root / "empty.x"
        source.write_text("// No executable code.\n", encoding="utf-8")
        snapshot = root / "snapshot"
        subprocess.run([tool, "snapshot", snapshot, source], check=True,
                       capture_output=True, text=True)
        invalid = [
            {"op": "find", "wher": {"name": "absent"}},
            {"op": "find", "where": {"all": [
                {"name": "absent"}, {"unknown": "value"}]}},
            {"op": "traverse", "select": {"name": "absent"},
             "relations": "calls"},
            {"op": "traverse", "select": {"name": "absent"},
             "relations": ["not-a-relation"]},
            {"op": "match", "pattern": "(call ?f (args *args))",
             "node_where": {"unknown": "value"}},
            {"op": "inspect", "select": {"name": "absent"},
             "view": "not-a-view"},
        ]
        valid = [
            {"op": "find", "where": {"name": "absent"}},
            {"op": "traverse", "select": {"name": "absent"},
             "relations": ["implements"]},
            {"op": "match", "pattern": "(call ?f (args *args))"},
        ]
        query_file = root / "query.json"
        for query in invalid + valid:
            query_file.write_text(json.dumps(query), encoding="utf-8")
            run = subprocess.run([tool, "query", snapshot, query_file],
                                 capture_output=True, text=True)
            if query in invalid:
                assert run.returncode != 0, (query, run.stdout)
                assert "bad-arg" in run.stderr, (query, run.stderr)
            else:
                assert run.returncode == 0, (query, run.stderr)
                assert json.loads(run.stdout)["total"] == 0, (query, run.stdout)
    print("snapshot query boundary passed")


if __name__ == "__main__":
    main()
