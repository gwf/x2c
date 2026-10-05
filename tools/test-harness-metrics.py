#!/usr/bin/env python3
"""Focused transcript tests using synthetic records only."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "harness_metrics", Path(__file__).with_name("harness-metrics.py"))
metrics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metrics)
DAY = "2026-10-01T12:00:00Z"


def item(kind, payload, stamp=DAY):
    return {"type": kind, "timestamp": stamp, "payload": payload}


def meta(session="full-session-a", cwd="/work/x2c"):
    return item("session_meta", {"id": session, "cwd": cwd},
                "2026-09-01T00:00:00Z")


def final(text="The change works.", stamp=DAY):
    return item("response_item", {
        "type": "message", "role": "assistant", "phase": "final_answer",
        "content": [{"type": "output_text", "text": text}],
    }, stamp)


class HarnessMetricsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def write(self, name, records):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(r) + "\n" for r in records))
        return str(path)

    def scan(self, paths, since="2026-10-01", until="2026-10-01"):
        coverage = {}
        result = metrics.scan_paths(paths, since, until, "x2c", coverage)
        return result, coverage

    def test_modern_and_legacy_reply_representations_count_once(self):
        event = item("event_msg", {
            "type": "agent_message", "phase": "final_answer",
            "message": "The change works.",
        })
        path = self.write("session.jsonl", [meta(), event, final(),
                          final(stamp="2026-10-01T13:00:00Z")])
        sessions, _ = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["replies"], 2)
        self.assertEqual(sessions[0]["reply_words"], [3, 3])

    def test_legacy_only_and_channel_final_are_supported(self):
        reply = final("Another answer.")
        reply["payload"].pop("phase")
        reply["payload"]["channel"] = "final"
        path = self.write("legacy.jsonl", [meta(), reply, item("event_msg", {
            "type": "agent_message", "phase": "final_answer",
            "message": "A legacy answer.",
        }, "2026-10-01T13:00:00Z")])
        sessions, _ = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["replies"], 2)

    def test_identical_answers_on_separate_turns_are_not_deduplicated(self):
        event = item("event_msg", {
            "type": "agent_message", "phase": "final_answer",
            "message": "The change works.",
        })
        user = item("response_item", {
            "type": "message", "role": "user",
            "content": [{"type": "input_text", "text": "Next question."}],
        })
        path = self.write("turns.jsonl", [meta(), event, user, final()])
        sessions, _ = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["replies"], 2)

    def test_complementary_files_merge_and_keep_original_metadata(self):
        tool = item("response_item", {
            "type": "function_call", "name": "exec_command", "call_id": "c1",
            "arguments": json.dumps({"cmd": "make check"}),
        })
        first = self.write("sessions/a.jsonl", [meta(), tool])
        second = self.write("archived_sessions/a.jsonl", [
            meta(), dict(tool, ordinal=7), meta("replayed", "/other"), final(),
        ])
        sessions, coverage = self.scan([(first, "codex"), (second, "codex")])
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["session"], "full-session-a")
        self.assertEqual(sessions[0]["counts"]["tool_calls"], 1)
        self.assertEqual(sessions[0]["counts"]["replies"], 1)
        self.assertEqual(sessions[0]["counts"]["make_gate_requests"], 1)
        self.assertEqual(coverage["codex"]["complementary_files"], 1)
        self.assertEqual(coverage["codex"]["duplicate_records"], 2)

    def test_worker_id_is_not_its_parent_session_id(self):
        own = meta("worker-id")
        own["payload"]["session_id"] = "parent-id"
        parent = meta("parent-id")
        worker = self.write("worker.jsonl", [own, parent, final()])
        main = self.write("main.jsonl", [parent, final()])
        sessions, _ = self.scan([(worker, "codex"), (main, "codex")])
        self.assertEqual({s["session"] for s in sessions},
                         {"worker-id", "parent-id"})

    def test_worker_does_not_count_replayed_activity_before_its_creation(self):
        own = meta("worker-id")
        own["timestamp"] = "2026-10-01T12:00:00Z"
        path = self.write("replay.jsonl", [own, meta("parent-id"),
            final("Parent answer.", "2026-10-01T11:59:00Z"),
            final("Worker answer.", "2026-10-01T12:01:00Z")])
        sessions, coverage = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["replies"], 1)
        self.assertEqual(coverage["codex"]["replayed_records"], 2)

    def test_replayed_outer_timestamps_do_not_become_worker_actions(self):
        own = meta("worker-id")
        own["timestamp"] = "2026-10-01T12:00:00Z"
        own["payload"]["timestamp"] = "2026-10-01T12:00:00Z"
        old_start = int(metrics.timestamp("2026-10-01T11:00:00Z").timestamp())
        own_start = int(metrics.timestamp(DAY).timestamp())
        path = self.write("rewritten.jsonl", [own,
            item("event_msg", {"type": "task_started", "started_at": old_start}),
            final("Inherited answer."),
            item("response_item", {"type": "function_call", "name": "exec_command",
                "arguments": json.dumps({"cmd": "make check"})}),
            item("event_msg", {"type": "thread_settings_applied",
                               "thread_id": "worker-id"}),
            item("event_msg", {"type": "task_started", "started_at": own_start}),
            final("Worker answer.", "2026-10-01T12:01:00Z")])
        sessions, coverage = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["replies"], 1)
        self.assertNotIn("tool_calls", sessions[0]["counts"])
        self.assertEqual(coverage["codex"]["replayed_records"], 3)

    def test_recursive_discovery_finds_archive_and_older_active_worker(self):
        live = self.write("sessions/2026/09/01/rollout-old.jsonl", [
            meta("older"), final()])
        archived = self.write("archived_sessions/old.jsonl", [
            meta("archived"), final()])
        worker = self.write("projects/work-x2c/a/subagents/worker.jsonl", [
            {"type": "assistant", "sessionId": "worker", "cwd": "/work/x2c",
             "timestamp": DAY, "message": {"content": [
                 {"type": "text", "text": "Worker answer."}]}}])
        paths = metrics.transcript_paths(str(self.root / "projects"),
                  str(self.root / "sessions"), "all", "x2c",
                  "2026-10-01", "2026-10-01")
        self.assertEqual(set(paths), {(live, "codex"), (archived, "codex"),
                                     (worker, "claude")})
        sessions, coverage = self.scan(paths)
        self.assertEqual(len(sessions), 3)
        self.assertEqual(coverage["claude"]["nested_worker_files"], 1)
        self.assertEqual(coverage["codex"]["archive_files"], 1)

    def test_exact_window_normalizes_offsets_and_excludes_upper_boundary(self):
        path = self.write("exact.jsonl", [meta(),
            final("Too early.", "2026-10-01T06:59:59Z"),
            final("At start.", "2026-10-01T00:00:00-07:00"),
            final("At end.", "2026-10-01T08:00:00Z")])
        sessions, _ = self.scan([(path, "codex")],
            "2026-10-01T00:00:00-07:00", "2026-10-01T01:00:00-07:00")
        self.assertEqual(sessions[0]["reply_words"], [2])
        self.assertEqual(sessions[0]["days"], ["2026-10-01"])

    def test_date_until_includes_entire_utc_day(self):
        path = self.write("dates.jsonl", [meta(),
            final(stamp="2026-10-01T23:59:59Z"),
            final(stamp="2026-10-02T00:00:00Z")])
        sessions, _ = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["replies"], 1)
        with self.assertRaises(ValueError):
            metrics.boundary("2026-10-01T00:00:00")

    def test_skills_come_from_frontmatter_not_directory_names(self):
        root = self.root / "skills"
        path = root / "new-directory/SKILL.md"
        path.parent.mkdir(parents=True)
        path.write_text('---\nname: "new-canonical-skill"\n---\nBody\n')
        self.assertEqual(metrics.project_skills(root), {"new-canonical-skill"})
        self.assertIn("orchestrate-x2c-work", metrics.PROJECT_SKILLS)

    def test_modern_edit_and_start_calls_are_not_doubled_by_legacy_events(self):
        path = self.write("tools.jsonl", [meta(),
            item("response_item", {"type": "custom_tool_call", "name": "apply_patch",
                "call_id": "edit1", "input": "*** Update File: src/main.x"}),
            item("event_msg", {"type": "patch_apply_end", "success": True,
                "call_id": "edit1", "changes": {"src/main.x": {}}}),
            item("response_item", {"type": "function_call", "name": "spawn_agent",
                "call_id": "start1", "arguments": "{}"}),
            item("event_msg", {"type": "sub_agent_activity", "kind": "started"})])
        sessions, _ = self.scan([(path, "codex")])
        self.assertEqual(sessions[0]["counts"]["edits"], 1)
        self.assertEqual(sessions[0]["counts"]["source_edits"], 1)
        self.assertEqual(sessions[0]["counts"]["subagents"], 1)

    def test_terminal_turns_and_tool_calls_merge_by_full_identity(self):
        def record(content, stamp=DAY):
            return {"type": "assistant", "timestamp": stamp,
                    "sessionId": "terminal-full-id", "cwd": "/work/x2c",
                    "message": {"content": content}}
        tool = record([{"type": "tool_use", "name": "Bash", "id": "bash1",
                        "input": {"command": "make check"}}])
        reply = record([{"type": "text", "text": "Final answer."}],
                       "2026-10-01T13:00:00Z")
        live = self.write("projects/x2c/live.jsonl", [tool])
        archive = self.write("projects/x2c/copied.jsonl", [tool, reply])
        sessions, _ = self.scan([(live, "claude"), (archive, "claude")])
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0]["counts"]["tool_calls"], 1)
        self.assertEqual(sessions[0]["counts"]["replies"], 1)
        self.assertEqual(sessions[0]["counts"]["make_gate_requests"], 1)

    def test_nested_workers_keep_distinct_parent_and_worker_identity(self):
        def worker(agent):
            return {"type": "assistant", "timestamp": DAY,
                    "sessionId": "shared-parent", "agentId": agent,
                    "cwd": "/work/x2c", "message": {"content": [
                        {"type": "text", "text": "Worker answer."}]}}
        a = self.write("projects/x2c/subagents/a.jsonl", [worker("a")])
        b = self.write("projects/x2c/subagents/b.jsonl", [worker("b")])
        duplicate = self.write("archive/a.jsonl", [worker("a")])
        sessions, coverage = self.scan([(a, "claude"), (b, "claude"),
                                       (duplicate, "claude")])
        self.assertEqual({s["session"] for s in sessions},
                         {"shared-parent:a", "shared-parent:b"})
        self.assertEqual(sum(s["counts"]["replies"] for s in sessions), 2)
        self.assertEqual(coverage["claude"]["complementary_files"], 1)

    def test_unavailable_fields_differ_from_supported_zero(self):
        path = self.write("reply.jsonl", [meta(), final()])
        sessions, _ = self.scan([(path, "codex")])
        summary = metrics.summarize(sessions)
        self.assertIn("edits", summary["unavailable_fields"])
        self.assertNotIn("edits", summary["counts"])
        self.assertIn("executed_checks", summary["unavailable_fields"])
        self.assertEqual(summary["counts"]["replies"], 1)
        terminal = self.write("projects/x2c/zero.jsonl", [{
            "type": "assistant", "timestamp": DAY, "sessionId": "zero",
            "cwd": "/work/x2c", "message": {"content": [
                {"type": "text", "text": "No edits were requested."}]}}])
        sessions, _ = self.scan([(terminal, "claude")])
        summary = metrics.summarize(sessions)
        self.assertEqual(summary["counts"]["edits"], 0)
        self.assertNotIn("edits", summary["unavailable_fields"])

    def test_cli_reports_coverage_without_raw_reply_content(self):
        self.write("sessions/old.jsonl", [meta(), final("PRIVATE_SENTINEL")])
        result = subprocess.run([sys.executable, str(Path(metrics.__file__)),
            "--agent", "codex", "--codex-root", str(self.root / "sessions"),
            "--since", "2026-10-01T00:00:00Z", "--until", "2026-10-02T00:00:00Z",
            "--json", "--per-session"], capture_output=True, text=True, check=True)
        report = json.loads(result.stdout)
        self.assertEqual(report["by_agent"]["codex"]["coverage"]["files"], 1)
        self.assertEqual(report["sessions"], 1)
        self.assertNotIn("PRIVATE_SENTINEL", result.stdout)


if __name__ == "__main__":
    unittest.main()
