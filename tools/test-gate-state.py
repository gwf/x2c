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

DOC_CHECK = ["make", "doc-check"]
DOC_OUTPUTS = ["make", "-o", "build", "doc-outputs"]
COMMANDS_CHECK = ["make", "-o", "build", "commands-check"]


class ScopedEvidence(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.page("docs/src/guide.md", "Text.\n\n```x2c\nint x;\n```\n")
        self.page("docs/src/prose.md", "Text.\n\n```c\nint x;\n```\n")
        root = patch.object(gate, "ROOT", self.root)
        root.start()
        self.addCleanup(root.stop)
        self.old = {"version": gate.FORMAT, "configuration": {"cc": "same"},
                    "recorded_at_head": "baseline", "files": {
                        "src/emit.x": "100000:0:compiler",
                        "docs/src/guide.md": "100000:0:old",
                        "docs/src/prose.md": "100000:0:old",
                        "commands/graph/main.x": "100000:0:old"}}
        self.new = copy.deepcopy(self.old)
        self.new["recorded_at_head"] = "merged"

    def page(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def change(self, path, value="100000:0:new"):
        self.new["files"][path] = value

    def test_plan_only_needs_documentation_check(self):
        self.change("plans/design.md")
        self.assertEqual(gate.incremental_steps(self.old, self.new),
                         [DOC_CHECK])

    def test_book_samples_are_checked_without_bootstrap(self):
        self.change("docs/src/guide.md")
        self.assertEqual(gate.incremental_steps(self.old, self.new),
                         [DOC_CHECK, DOC_OUTPUTS])

    def test_indented_sample_fence_counts(self):
        self.page("docs/src/guide.md", "1. Item:\n\n   ```x2c,ignore\n   x\n"
                  "   ```\n")
        self.change("docs/src/guide.md")
        self.assertIn(DOC_OUTPUTS, gate.incremental_steps(self.old, self.new))

    def test_book_page_without_samples_needs_no_outputs(self):
        self.change("docs/src/prose.md")
        self.assertEqual(gate.incremental_steps(self.old, self.new),
                         [DOC_CHECK])

    def test_deleted_book_page_needs_no_outputs(self):
        (self.root / "docs/src/guide.md").unlink()
        del self.new["files"]["docs/src/guide.md"]
        self.assertEqual(gate.incremental_steps(self.old, self.new),
                         [DOC_CHECK])

    def test_commands_check_consumers_and_cli(self):
        self.change("commands/graph/main.x")
        steps = gate.incremental_steps(self.old, self.new)
        self.assertIn(COMMANDS_CHECK, steps)
        self.assertIn(["bash", "unittest/probes/run-cli-boundary.sh"], steps)
        self.assertNotIn(["make", "agent-pr-check"], steps)

    def test_command_markdown_fixture_runs_command_tests(self):
        self.change("commands/bind/tests/expected/README.md")
        self.assertIn(COMMANDS_CHECK,
                      gate.incremental_steps(self.old, self.new))

    def test_core_build_and_tool_changes_need_full_gate(self):
        for path in ("src/emit.x", "lib/map.x", "bootstrap/src/emit.c",
                     "Makefile", "tools/land-dev", "commands/parallel.sh",
                     "commands/build/build.x", "commands/build/README.md",
                     "etc/compiler-prelude.x"):
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
        self.assertIn(COMMANDS_CHECK,
                      gate.incremental_steps(self.old, self.new))

    def test_documentation_rule(self):
        for path, expected in (("plans/design.md", True),
                               ("examples/README.md", True),
                               ("site/public/llms.txt", True),
                               ("commands/repl/README.md", False),
                               ("docs/src/syntax/x2c.ebnf", False),
                               ("src/emit.x", False)):
            with self.subTest(path=path):
                self.assertEqual(gate.documentation(path), expected)

    def ensure(self, name="agent-pr-check", records=None, returncode=0,
               after=None):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "state.json"
            with patch.object(gate, "STATE", state):
                gate.save({"agent-pr-check": self.old}
                          if records is None else records)
                with (patch.object(gate, "cmd_check", return_value=1),
                      patch.object(gate, "digest", side_effect=[
                          self.new, after or self.new]),
                      patch.object(gate.subprocess, "run") as run):
                    run.return_value.returncode = returncode
                    result = gate.cmd_ensure(name)
                    self.steps = [call.args[0] for call in run.call_args_list]
                return result, gate.load().get(name)

    def test_success_records_exact_tree_and_reused_evidence(self):
        self.change("plans/design.md")
        result, record = self.ensure()
        self.assertEqual(result, 0)
        self.assertEqual(self.steps, [DOC_CHECK])
        self.assertEqual(record["files"], self.new["files"])
        self.assertEqual(record["reused_from_head"], "baseline")
        self.assertEqual(record["completed_steps"], [DOC_CHECK])

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

    def test_doc_check_runs_samples_of_a_page_changed_since_a_record(self):
        self.change("docs/src/guide.md")
        result, record = self.ensure("doc-check")
        self.assertEqual(result, 0)
        self.assertEqual(self.steps, [DOC_CHECK, DOC_OUTPUTS])
        self.assertNotIn("reused_from_head", record)
        self.assertEqual(record["completed_steps"], [DOC_CHECK, DOC_OUTPUTS])

    def test_doc_check_skips_samples_that_a_record_holds(self):
        self.change("plans/design.md")
        self.change("docs/src/prose.md")
        result, _ = self.ensure("doc-check")
        self.assertEqual(result, 0)
        self.assertEqual(self.steps, [DOC_CHECK])

    def test_doc_check_trusts_a_page_held_by_either_record(self):
        self.change("docs/src/guide.md")
        self.change("plans/design.md")
        documented = copy.deepcopy(self.new)
        documented["files"]["plans/design.md"] = "100000:0:older"
        result, _ = self.ensure("doc-check", records={
            "agent-pr-check": self.old, "doc-check": documented})
        self.assertEqual(result, 0)
        self.assertEqual(self.steps, [DOC_CHECK])

    def test_doc_check_without_a_record_checks_every_sample(self):
        for records in ({}, {"agent-pr-check": {**self.old, "version": 6}}):
            with self.subTest(records=records):
                result, _ = self.ensure("doc-check", records=records)
                self.assertEqual(result, 0)
                self.assertEqual(self.steps, [DOC_CHECK, DOC_OUTPUTS])

    def test_doc_check_may_regenerate_build_outputs(self):
        self.change("docs/src/prose.md")
        moved = copy.deepcopy(self.new)
        moved["files"]["lib/x2c.x"] = "100000:0:regenerated"
        result, record = self.ensure("doc-check", after=moved)
        self.assertEqual(result, 0)
        self.assertEqual(record["files"], moved["files"])


if __name__ == "__main__":
    unittest.main()
