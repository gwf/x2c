#!/usr/bin/env python3
"""Focused tests for agent transcript measurement and incident indexing."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


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
        self.assertEqual(result["counts"]["make_gate_requests"], 3)
        self.assertEqual(result["counts"]["ensure_gate_requests"], 0)
        self.assertNotIn("broad_gates_redundant", result["counts"])
        self.assertEqual(result["counts"]["source_edits"], 1)
        self.assertEqual(result["counts"]["push_refspec"], 1)
        self.assertEqual(result["counts"]["skill_project"], 1)
        self.assertEqual(result["skills"], {"fix-x2c-bug": 1})
        self.assertEqual(result["counts"]["replies_furniture"], 1)

    def scan_commands(self, agent, commands):
        if agent == "codex":
            records = [codex_records()[0]]
            records.extend({
                "type": "response_item",
                "payload": {
                    "type": "function_call",
                    "arguments": json.dumps({"cmd": command}),
                },
            } for command in commands)
        else:
            records = [{
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Bash",
                    "input": {"command": command},
                }]},
            } for command in commands]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "transcript.jsonl"
            write_jsonl(path, records)
            if agent == "codex":
                return METRICS.codex_session(str(path), None, None, "x2c")
            return METRICS.scan_session(str(path), None, None)

    def test_ensure_requests_are_not_make_requests(self):
        command = "tools/gate-state.py ensure agent-pr-check"
        for agent in ("claude", "codex"):
            with self.subTest(agent=agent):
                result = self.scan_commands(agent, [command, command])
                counts = result["counts"]
                self.assertEqual(counts["ensure_gate_requests"], 2)
                self.assertEqual(counts["make_gate_requests"], 0)
                self.assertEqual(counts.get("make_canonical", 0), 0)
                self.assertEqual(result["targets"], {"agent-pr-check": 2})
                summary = METRICS.summarize([result])
                self.assertNotIn("broad_gates", summary["counts"])
                self.assertNotIn("broad_gates_redundant", summary["counts"])
                self.assertNotIn(
                    "broad_gates_redundant", summary["rates_percent"]
                )

    def test_make_and_ensure_requests_keep_targets_and_aliases(self):
        commands = [
            "make check && ./tools/gate-state.py ensure doc-check "
            "&& make stage-3",
            "time tools/gate-state.py ensure agent-pr-check",
            "make doc-check && make safely && make build",
            "echo \"don't count this; make check\" && make verify-sanitize",
        ]
        for agent in ("claude", "codex"):
            with self.subTest(agent=agent):
                result = self.scan_commands(agent, commands)
                counts = result["counts"]
                self.assertEqual(counts["ensure_gate_requests"], 2)
                self.assertEqual(counts["make_gate_requests"], 5)
                self.assertEqual(counts["make_canonical"], 5)
                self.assertEqual(counts["make_alias"], 1)
                self.assertEqual(result["targets"], {
                    "check": 1, "doc-check": 2, "stage-3": 1,
                    "agent-pr-check": 1, "safely": 1, "build": 1,
                    "verify-sanitize": 1,
                })

    def test_quoted_commands_are_not_requests(self):
        commands = [
            'pgrep -f "worker; tools/gate-state.py ensure agent-pr-check"',
            "echo 'next; make agent-pr-check'",
            'printf "%s\\n" "make check; make stage-3"',
            'echo "tools/gate-state.py ensure doc-check"',
            r'echo "say \"; make check; tools/gate-state.py ensure doc-check"',
        ]
        for agent in ("claude", "codex"):
            with self.subTest(agent=agent):
                result = self.scan_commands(agent, commands)
                self.assertEqual(result["targets"], {})
                self.assertEqual(result["counts"]["make_gate_requests"], 0)
                self.assertEqual(result["counts"]["ensure_gate_requests"], 0)

    def test_documented_by_day_command_runs_for_codex(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            transcript = (
                root / "codex" / "2026" / "08" / "09" /
                "rollout-2026-08-09T12.jsonl"
            )
            write_jsonl(transcript, codex_records())
            command = [
                sys.executable,
                str(TOOLS / "harness-metrics.py"),
                "--agent", "codex",
                "--codex-root", str(root / "codex"),
                "--match", "x2c",
                "--by-day",
            ]
            done = subprocess.run(
                [*command, "--json"], capture_output=True,
                text=True, check=True,
            )
            displayed = subprocess.run(
                command, capture_output=True, text=True, check=True,
            )
        self.assertIn("make_gates=3", displayed.stdout)
        self.assertIn("ensure_gates=0", displayed.stdout)
        self.assertNotIn("redundant", displayed.stdout)
        report = json.loads(done.stdout)
        self.assertEqual(report["sessions"], 1)
        self.assertEqual(list(report["by_day"]), ["2026-08-09"])


class IncidentTests(unittest.TestCase):
    def make_repository(self, root: Path) -> None:
        def git(*args):
            subprocess.run(
                ["git", *args], cwd=root, check=True, capture_output=True,
                text=True,
            )

        git("init", "-b", "main")
        git("config", "user.name", "Harness Test")
        git("config", "user.email", "harness@example.invalid")
        (root / "baseline.txt").write_text("baseline\n", encoding="utf-8")
        git("add", "baseline.txt")
        git("-c", "commit.gpgsign=false", "commit", "-m", "baseline")
        git("update-ref", "refs/remotes/origin/main", "HEAD")
        (root / "change.txt").write_text("change\n", encoding="utf-8")
        git("add", "change.txt")
        git("-c", "commit.gpgsign=false", "commit", "-m", "workspace change")

    def test_existing_workspace_compares_against_main(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_repository(Path(directory))
            result = FAILURE.git_state(directory)

        diff = result.split("$ git diff --stat origin/main...HEAD\n")[1]
        diff = diff.split("$ git stash list")[0]
        self.assertIn("change.txt", diff)
        self.assertIn("1 file changed, 1 insertion(+)", diff)

    def test_missing_workspace_reads_main_from_shared_clone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_repository(root)
            missing = root / "workspaces" / "deleted"
            with patch.dict(FAILURE.os.environ, {
                "CONDUCTOR_ROOT_PATH": directory,
                "CONDUCTOR_WORKSPACE_PATH": str(missing.with_name("current")),
            }):
                result = FAILURE.git_state(str(missing))

        self.assertIn("log --oneline -20 origin/main\n", result)
        self.assertIn("baseline", result)
        self.assertNotIn("workspace change", result)

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


if __name__ == "__main__":
    unittest.main()
