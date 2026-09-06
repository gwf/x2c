#!/usr/bin/env python3
"""Focused tests for agent transcript measurement and incident indexing."""

from __future__ import annotations

import collections
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


TOOLS = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    assert spec.loader
    spec.loader.exec_module(module)
    return module


METRICS = load("harness_metrics", TOOLS / "harness-metrics.py")
FAILURE = load("agent_failure", TOOLS / "agent-failure.py")
REPLY = load("reply_check", TOOLS / "reply-check.py")


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(record) + "\n" for record in records),
        encoding="utf-8",
    )


def codex_records() -> list[dict]:
    stamp = "2026-08-09T12:00:00Z"
    command = (
        "sed -n '1,20p' agents/skills/fix-x2c-bug/SKILL.md && "
        "make agent-pr-check && "
        "git push -u origin HEAD:refs/heads/topic"
    )
    call = lambda value, call_id: {
        "type": "response_item",
        "timestamp": stamp,
        "payload": {
            "type": "custom_tool_call",
            "name": "exec",
            "input": f"const x = tools.exec_command({{\"cmd\":{json.dumps(value)}}});",
            "call_id": call_id,
        },
    }
    return [
        {
            "type": "session_meta",
            "timestamp": stamp,
            "payload": {
                "session_id": "12345678-full-session",
                "cwd": "/tmp/x2c-test",
            },
        },
        call(command, "one"),
        {
            "type": "event_msg",
            "timestamp": stamp,
            "payload": {
                "type": "patch_apply_end",
                "call_id": "patch-one",
                "success": True,
                "changes": {"/tmp/x2c-test/src/main.x": {"type": "update"}},
            },
        },
        call("make agent-pr-check", "two"),
        call("make agent-pr-check", "three"),
        {
            "type": "event_msg",
            "timestamp": stamp,
            "payload": {
                "type": "agent_message",
                "phase": "final_answer",
                "message": "# Result\n\n- verified",
            },
        },
    ]


class HarnessMetricsTests(unittest.TestCase):
    def test_codex_session_measures_commands_edits_skills_and_reply(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rollout-2026-08-09T12.jsonl"
            write_jsonl(path, codex_records())
            result = METRICS.codex_session(str(path), None, None, "x2c")

        self.assertEqual(result["session"], "12345678")
        self.assertEqual(result["counts"]["broad_gates"], 3)
        self.assertEqual(result["counts"]["broad_gates_redundant"], 1)
        self.assertEqual(result["counts"]["source_edits"], 1)
        self.assertEqual(result["counts"]["push_refspec"], 1)
        self.assertEqual(result["counts"]["skill_project"], 1)
        self.assertEqual(result["skills"], {"fix-x2c-bug": 1})
        self.assertEqual(result["counts"]["replies_furniture"], 1)

    def test_gate_ensure_counts_the_target_and_redundant_invocations(self):
        command = "tools/gate-state.py ensure agent-pr-check"
        self.assertEqual(list(METRICS.make_targets(command)), ["agent-pr-check"])
        self.assertEqual(
            list(METRICS.make_targets(f'pgrep -f "worker; {command}"')),
            [],
        )
        self.assertEqual(
            list(METRICS.make_targets(f"time {command}")),
            ["agent-pr-check"],
        )
        self.assertEqual(
            list(METRICS.make_targets(
                "make check && tools/gate-state.py ensure doc-check "
                "&& make stage-3"
            )),
            ["check", "doc-check", "stage-3"],
        )

        stat = collections.Counter()
        targets = collections.Counter()
        edits_since_gate = {}
        changes = METRICS.count_command(
            command, stat, targets, edits_since_gate, 0
        )
        METRICS.count_command(
            command, stat, targets, edits_since_gate, changes
        )

        self.assertEqual(targets["agent-pr-check"], 2)
        self.assertEqual(stat["make_canonical"], 2)
        self.assertEqual(stat["broad_gates"], 2)
        self.assertEqual(stat["broad_gates_redundant"], 1)

    def test_documented_by_day_command_runs_for_codex(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            transcript = (
                root / "codex" / "2026" / "08" / "09" /
                "rollout-2026-08-09T12.jsonl"
            )
            write_jsonl(transcript, codex_records())
            done = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS / "harness-metrics.py"),
                    "--agent", "codex",
                    "--codex-root", str(root / "codex"),
                    "--match", "x2c",
                    "--by-day",
                    "--json",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
        report = json.loads(done.stdout)
        self.assertEqual(report["sessions"], 1)
        self.assertEqual(list(report["by_day"]), ["2026-08-09"])


class IncidentTests(unittest.TestCase):
    def test_index_append_is_idempotent(self):
        row = "| 2026-08-09 | diligence | report | `12345678` | `/tmp/x` | open |"
        with tempfile.TemporaryDirectory() as directory:
            index = Path(directory) / "agent-failures.md"
            index.write_text(
                "| Date | Kind | What was reported | Session | Evidence | Status |\n"
                "|---|---|---|---|---|---|\n",
                encoding="utf-8",
            )
            self.assertTrue(FAILURE.append_index(str(index), row))
            self.assertFalse(FAILURE.append_index(str(index), row))
            self.assertEqual(index.read_text().count(row), 1)

    def test_reply_hook_is_only_a_wall_of_text_backstop(self):
        self.assertEqual(REPLY.complaint("word " * 250), "")
        self.assertIn("251 words", REPLY.complaint("word " * 251))


if __name__ == "__main__":
    unittest.main()
