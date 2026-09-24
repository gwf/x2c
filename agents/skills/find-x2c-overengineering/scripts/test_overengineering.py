#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("overengineering.py")
SPEC = importlib.util.spec_from_file_location("overengineering", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


def git(root, *args):
    return subprocess.run(
        ["git", *args], cwd=root, text=True, capture_output=True, check=True
    ).stdout


class ForensicsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        (self.root / "src").mkdir()
        (self.root / "lib").mkdir()
        git(self.root, "init", "-q")
        git(self.root, "config", "user.email", "test@example.com")
        git(self.root, "config", "user.name", "Test")

    def tearDown(self):
        self.temp.cleanup()

    def commit(self, subject):
        git(self.root, "add", ".")
        git(self.root, "commit", "-qm", subject)
        return git(self.root, "rev-parse", "HEAD").strip()

    def test_deleted_ranges_cover_replacement_deleted_file_and_exclusion(self):
        (self.root / "src/a.x").write_text("one\ntwo\nthree\n")
        (self.root / "lib/gone.x").write_text("gone one\ngone two\n")
        (self.root / "lib/x2c.x").write_text("generated\n")
        self.commit("add source")
        (self.root / "src/a.x").write_text("one\nreplacement\n")
        (self.root / "lib/gone.x").unlink()
        (self.root / "lib/x2c.x").unlink()
        deletion = self.commit("remove source")
        ranges = MODULE.parse_diff(deletion, self.root)
        self.assertIn(("src/a.x", 2, 2), ranges)
        self.assertIn(("lib/gone.x", 1, 2), ranges)
        self.assertFalse(any(path == "lib/x2c.x" for path, _, _ in ranges))
        report = MODULE.deletion_report(deletion, self.root)
        self.assertEqual(report["removed_parent_lines"], 4)
        self.assertTrue(report["origins"][0]["provenance_wall"])

    def test_deleted_range_uses_old_name_across_rename(self):
        (self.root / "src/old.x").write_text("keep\nremove\n")
        self.commit("add old name")
        git(self.root, "mv", "src/old.x", "src/new.x")
        (self.root / "src/new.x").write_text("keep\n")
        deletion = self.commit("rename and trim")
        ranges = MODULE.parse_diff(deletion, self.root)
        self.assertTrue(any(path == "src/old.x" and start <= 2 < start + count
                            for path, start, count in ranges))

    def test_cumulative_state_deduplicates_only_same_digest(self):
        base = self.root / "state"
        run = base / "runs/one"
        run.mkdir(parents=True)
        (run / "selection.json").write_text(json.dumps({"selected": [
            {"candidate_id": "src/a.x:_state", "source_digest": "old"}
        ]}))
        attempts = run / "attempts.jsonl"
        attempts.write_text('{"candidate_id":"src/a.x:_state",'
                            '"outcome":"empty"}\n')
        attempted = MODULE.previous_attempts(base)
        self.assertIn(("src/a.x:_state", "old"), attempted)
        self.assertNotIn(("src/a.x:_state", "new"), attempted)
        self.assertIn('"outcome":"empty"', attempts.read_text())

    def test_source_scope_excludes_generated_and_nonproduction(self):
        (self.root / "src/a.x").write_text("")
        (self.root / "lib/b.x").write_text("")
        (self.root / "lib/x2c.x").write_text("")
        (self.root / "examples").mkdir()
        (self.root / "examples/e.x").write_text("")
        got = [path.relative_to(self.root).as_posix()
               for path in MODULE.source_paths(self.root)]
        self.assertEqual(got, ["lib/b.x", "src/a.x"])

    def test_selection_uses_one_slot_per_source_neighborhood(self):
        regions = [
            {"candidate_id": "src/a.x:_cache_one", "path": "src/a.x",
             "start": 10, "end": 20, "public": False,
             "source_digest": "one"},
            {"candidate_id": "src/a.x:_cache_two", "path": "src/a.x",
             "start": 22, "end": 30, "public": False,
             "source_digest": "two"},
            {"candidate_id": "src/a.x:_other", "path": "src/a.x",
             "start": 200, "end": 220, "public": False,
             "source_digest": "three"},
        ]
        selected = MODULE.bounded_selection(regions, set(), 3)
        self.assertEqual(
            [item["candidate_id"] for item in selected],
            ["src/a.x:_cache_one", "src/a.x:_other"],
        )


if __name__ == "__main__":
    unittest.main()
