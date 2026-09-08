#!/usr/bin/env python3
"""Focused tests for publication gate reuse and recording."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


TOOLS = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    assert spec.loader
    spec.loader.exec_module(module)
    return module


GATE_STATE = load("gate_state", TOOLS / "gate-state.py")


class EnsureTests(unittest.TestCase):
    def test_valid_record_is_reused_without_running_gate(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check", return_value=0),
            mock.patch.object(GATE_STATE, "run_gate") as run_gate,
            mock.patch.object(GATE_STATE, "cmd_record") as record,
        ):
            result = GATE_STATE.cmd_ensure("doc-check")

        self.assertEqual(result, 0)
        run_gate.assert_not_called()
        record.assert_not_called()

    def test_stale_record_runs_corresponding_make_target(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check", return_value=1),
            mock.patch.object(GATE_STATE, "run_gate", return_value=0) as run_gate,
            mock.patch.object(GATE_STATE, "cmd_record", return_value=0),
        ):
            result = GATE_STATE.cmd_ensure("agent-pr-check")

        self.assertEqual(result, 0)
        run_gate.assert_called_once_with("agent-pr-check")

    def test_successful_gate_records_resulting_tree(self):
        before = {
            "version": GATE_STATE.FORMAT,
            "files": {"tracked": "before"},
            "compiler": "test cc",
            "recorded_at_head": "abc",
        }
        after = {**before, "files": {"tracked": "after"}}
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "gate-state.json"
            with (
                mock.patch.object(GATE_STATE, "STATE", state),
                mock.patch.object(
                    GATE_STATE, "digest", side_effect=[before, after]
                ),
                mock.patch.object(
                    GATE_STATE, "run_gate", return_value=0
                ) as run_gate,
                mock.patch("sys.stdout", new_callable=io.StringIO),
            ):
                result = GATE_STATE.cmd_ensure("doc-check")

            records = json.loads(state.read_text())

        self.assertEqual(result, 0)
        run_gate.assert_called_once_with("doc-check")
        self.assertEqual(records["doc-check"], after)

    def test_unknown_gate_is_rejected(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check") as check,
            mock.patch.object(GATE_STATE, "run_gate") as run_gate,
            mock.patch.object(GATE_STATE, "cmd_record") as record,
            mock.patch("sys.stderr", new_callable=io.StringIO) as stderr,
        ):
            result = GATE_STATE.cmd_ensure("check")

        self.assertEqual(result, 2)
        self.assertIn("unknown gate 'check'", stderr.getvalue())
        check.assert_not_called()
        run_gate.assert_not_called()
        record.assert_not_called()

    def test_failed_gate_returns_status_without_recording(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check", return_value=1),
            mock.patch.object(GATE_STATE, "run_gate", return_value=7),
            mock.patch.object(GATE_STATE, "cmd_record") as record,
        ):
            result = GATE_STATE.cmd_ensure("doc-check")

        self.assertEqual(result, 7)
        record.assert_not_called()

    def test_gate_output_is_inherited_live(self):
        completed = mock.Mock(returncode=0)
        with mock.patch.object(
            GATE_STATE.subprocess, "run", return_value=completed
        ) as run:
            result = GATE_STATE.run_gate("doc-check")

        self.assertEqual(result, 0)
        run.assert_called_once_with(
            ["make", "doc-check"], cwd=GATE_STATE.ROOT, check=False
        )


class ExistingCommandTests(unittest.TestCase):
    def test_record_and_check_still_store_and_reuse_any_named_gate(self):
        stamp = {
            "version": GATE_STATE.FORMAT,
            "files": {"tracked": "1234"},
            "compiler": "test cc",
            "recorded_at_head": "abc",
        }
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(
                GATE_STATE, "STATE", Path(directory) / "gate-state.json"
            ),
            mock.patch.object(GATE_STATE, "digest", return_value=stamp),
            mock.patch("sys.stdout", new_callable=io.StringIO),
        ):
            self.assertEqual(GATE_STATE.cmd_record("custom-gate"), 0)
            self.assertEqual(GATE_STATE.cmd_check("custom-gate"), 0)


class TreeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="x2c-gate-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.object(GATE_STATE, "ROOT", self.root))
        stack.enter_context(mock.patch.object(
            GATE_STATE, "STATE", self.root / "debug/gate-state.json"
        ))
        stack.enter_context(mock.patch("sys.stdout", new_callable=io.StringIO))
        self.git("init", "-q")
        self.git("config", "user.name", "Gate Test")
        self.git("config", "user.email", "gate@example.invalid")
        self.git("config", "core.filemode", "true")
        self.git("config", "core.autocrlf", "false")
        (self.root / ".gitignore").write_text("debug/\n")
        (self.root / "input").write_text("one\n")
        (self.root / "run.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.root / "run.sh").chmod(0o755)
        (self.root / "link").symlink_to("input")
        self.commit()

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, check=True, capture_output=True,
            text=True,
        ).stdout

    def commit(self):
        self.git("add", "-A")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "snapshot")

    def record(self):
        self.assertEqual(GATE_STATE.cmd_record("doc-check"), 0)

    def valid(self):
        self.assertEqual(GATE_STATE.cmd_check("doc-check"), 0)

    def stale(self):
        self.assertEqual(GATE_STATE.cmd_check("doc-check"), 1)

    def test_content_changes_and_staging_or_commit_without_changes(self):
        self.record()
        (self.root / "input").write_text("two\n")
        self.stale()
        self.record()
        self.git("add", "input")
        self.valid()
        self.commit()
        self.valid()

    def test_executable_changes_even_when_git_ignores_filemode(self):
        self.record()
        path = self.root / "run.sh"
        path.chmod(0o644)
        self.stale()
        self.record()
        self.git("add", "run.sh")
        self.valid()
        self.git("config", "core.filemode", "false")
        path.chmod(0o755)
        self.stale()

    def test_symlink_target_bytes_and_type_are_distinct(self):
        (self.root / "other").write_text("one\n")
        self.commit()
        self.record()
        link = self.root / "link"
        link.unlink()
        link.symlink_to("other")
        self.stale()
        self.record()
        self.git("add", "link")
        self.valid()
        link.unlink()
        link.write_text("other")
        self.stale()
        self.record()
        self.git("add", "link")
        self.valid()

    def test_dangling_symlinks_survive_staging_and_target_creation(self):
        path = self.root / "dangling"
        path.symlink_to("debug/missing")
        self.record()
        self.git("add", "dangling")
        self.valid()
        (self.root / "debug/missing").write_text("ignored target\n")
        self.valid()
        path.unlink()
        path.symlink_to("debug/different")
        self.stale()

    def test_deletions_and_new_files_survive_staging(self):
        self.record()
        (self.root / "input").unlink()
        self.stale()
        self.record()
        self.git("add", "-A")
        self.valid()
        self.commit()
        self.valid()
        (self.root / "new").write_text("new\n")
        self.stale()
        self.record()
        self.git("add", "new")
        self.valid()

    def test_ignored_files_do_not_invalidate(self):
        self.record()
        (self.root / "debug/log").write_text("output\n")
        self.valid()

    def test_old_records_are_unknown(self):
        self.record()
        records = GATE_STATE.load()
        records["doc-check"]["version"] = GATE_STATE.FORMAT - 1
        GATE_STATE.save(records)
        self.stale()

    def test_clean_files_reuse_index_content_hashes(self):
        with mock.patch.object(
            GATE_STATE, "content_hash", wraps=GATE_STATE.content_hash
        ) as content_hash:
            GATE_STATE.digest()
        content_hash.assert_not_called()

    def install_cli(self):
        (self.root / "tools").mkdir()
        script = self.root / "tools/gate-state.py"
        shutil.copy2(TOOLS / "gate-state.py", script)
        return script

    def test_failed_git_inventory_cannot_record_or_reuse(self):
        script = self.install_cli()
        self.record()
        before = GATE_STATE.STATE.read_bytes()
        (self.root / ".git").rename(self.root / ".git-unavailable")
        for command in ("check", "record", "ensure"):
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, str(script), command, "doc-check"],
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("valid -", result.stdout)
                self.assertEqual(GATE_STATE.STATE.read_bytes(), before)

    def test_ensure_runs_make_only_when_needed_and_never_records_failure(self):
        script = self.install_cli()
        (self.root / "Makefile").write_text(
            "doc-check:\n"
            "\t@mkdir -p debug\n"
            "\t@cat input >> debug/executions\n"
            "\t@test ! -e fail\n"
        )
        self.commit()
        def ensure():
            return subprocess.run(
                [sys.executable, str(script), "ensure", "doc-check"],
                capture_output=True, text=True,
            )
        self.assertEqual(ensure().returncode, 0)
        self.assertEqual(ensure().returncode, 0)
        runs = self.root / "debug/executions"
        self.assertEqual(runs.read_text(), "one\n")
        (self.root / "run.sh").chmod(0o644)
        self.assertEqual(ensure().returncode, 0)
        self.assertEqual(runs.read_text(), "one\none\n")
        before = GATE_STATE.STATE.read_bytes()
        (self.root / "fail").touch()
        self.assertNotEqual(ensure().returncode, 0)
        self.assertEqual(GATE_STATE.STATE.read_bytes(), before)
        self.stale()


if __name__ == "__main__":
    unittest.main()
