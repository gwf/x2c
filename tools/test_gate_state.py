#!/usr/bin/env python3
"""Focused tests for publication gate reuse and recording."""

from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
