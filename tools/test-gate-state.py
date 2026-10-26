#!/usr/bin/env python3
"""Optional offline probes for scoped publication evidence; no Make gates run."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "gate_state", Path(__file__).with_name("gate-state.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ScopedEvidence(unittest.TestCase):
    def setUp(self):
        self.old = {"version": gate.FORMAT, "configuration": {"cc": "same"},
                    "recorded_at_head": "baseline", "files": {
                        "src/emit.x": "100000:0:compiler",
                        "docs/src/guide.md": "100000:0:old",
                        "commands/graph/main.x": "100000:0:old"}}
        self.new = copy.deepcopy(self.old)
        self.new["recorded_at_head"] = "merged"

    def change(self, path, value="100000:0:new"):
        self.new["files"][path] = value

    def test_plan_only_needs_documentation_check(self):
        self.change("plans/design.md")
        self.assertEqual(gate.incremental_steps(self.old, self.new),
                         [["make", "doc-check"]])

    def test_book_examples_are_checked_without_bootstrap(self):
        self.change("docs/src/guide.md")
        self.assertEqual(gate.incremental_steps(self.old, self.new),
                         [["make", "doc-check"],
                          ["make", "-o", "build", "doc-outputs"]])

    def test_commands_check_consumers_and_cli(self):
        self.change("commands/graph/main.x")
        steps = gate.incremental_steps(self.old, self.new)
        self.assertIn(["make", "-o", "build", "commands-check"], steps)
        self.assertIn(["bash", "unittest/probes/run-cli-boundary.sh"], steps)
        self.assertNotIn(["make", "agent-pr-check"], steps)

    def test_core_build_and_tool_changes_need_full_gate(self):
        for path in ("src/emit.x", "lib/map.x", "bootstrap/src/emit.c",
                     "Makefile", "tools/land-dev", "commands/parallel.sh",
                     "commands/build/build.x", "etc/compiler-prelude.x"):
            with self.subTest(path=path):
                self.new = copy.deepcopy(self.old)
                self.change(path)
                self.assertIsNone(gate.incremental_steps(self.old, self.new))
        self.new = copy.deepcopy(self.old)
        self.new["configuration"] = {"cc": "different"}
        self.assertIsNone(gate.incremental_steps(self.old, self.new))

    def test_symlinks_and_executable_markdown_need_full_gate(self):
        for mode in ("120000:0:link", "100000:111:script"):
            self.change("docs/src/guide.md", mode)
            self.assertIsNone(gate.incremental_steps(self.old, self.new))

    def test_deleted_command_is_checked(self):
        del self.new["files"]["commands/graph/main.x"]
        self.assertIn(["make", "-o", "build", "commands-check"],
                      gate.incremental_steps(self.old, self.new))

    def ensure(self, returncode=0, after=None):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "state.json"
            with patch.object(gate, "STATE", state):
                gate.save({"agent-pr-check": self.old})
                with (patch.object(gate, "cmd_check", return_value=1),
                      patch.object(gate, "digest", side_effect=[
                          self.new, after or self.new]),
                      patch.object(gate, "run_gate") as full,
                      patch.object(gate.subprocess, "run") as run):
                    run.return_value.returncode = returncode
                    result = gate.cmd_ensure("agent-pr-check")
                    full.assert_not_called()
                return result, gate.load()["agent-pr-check"]

    def test_success_records_exact_tree_and_reused_evidence(self):
        self.change("plans/design.md")
        result, record = self.ensure()
        self.assertEqual(result, 0)
        self.assertEqual(record["files"], self.new["files"])
        self.assertEqual(record["reused_from_head"], "baseline")
        self.assertEqual(record["completed_steps"], [["make", "doc-check"]])

    def test_failure_preserves_previous_receipt(self):
        self.change("commands/graph/main.x")
        result, record = self.ensure(returncode=1)
        self.assertEqual(result, 1)
        self.assertEqual(record, self.old)

    def test_concurrent_authored_change_cannot_be_recorded(self):
        self.change("plans/design.md")
        moved = copy.deepcopy(self.new)
        moved["files"]["src/emit.x"] = "100000:0:changed-during-check"
        result, record = self.ensure(after=moved)
        self.assertEqual(result, 1)
        self.assertEqual(record, self.old)

    def test_consumer_check_cannot_change_bootstrap(self):
        self.change("commands/graph/main.x")
        moved = copy.deepcopy(self.new)
        moved["files"]["bootstrap/src/emit.c"] = "100000:0:unexpected"
        result, record = self.ensure(after=moved)
        self.assertEqual(result, 1)
        self.assertEqual(record, self.old)


if __name__ == "__main__":
    unittest.main()
