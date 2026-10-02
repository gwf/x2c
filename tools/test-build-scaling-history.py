#!/usr/bin/env python3
"""Focused tests for build-cost history identity retention."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("build-scaling-history.py")
SPEC = importlib.util.spec_from_file_location("build_scaling_history", SCRIPT)
assert SPEC and SPEC.loader
history = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(history)


class BuildScalingHistoryTests(unittest.TestCase):
  def test_nightly_legacy_row_replaces_replay_row_for_same_commit(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      commit = "a" * 40
      (root / "replay.csv").write_text(
        "commit,date,source_lines,cycles_per_line\n"
        f"{commit},2026-10-01,100,123\n",
        encoding="utf-8",
      )
      (root / "replay-child-cpu-v1.csv").write_text(
        "commit,date,metric_id,baseline_id,"
        "cpu_seconds_per_authored_line,score\n"
        f"{commit},2026-10-01,{history.scaling.METRIC_ID},base-cpu,"
        "0.01,100\n",
        encoding="utf-8",
      )
      (root / "history.jsonl").write_text(json.dumps({
        "commit": commit, "local_date": "2026-10-01",
        "build_scaling": {
          "cycles_per_line": 123.0, "source_lines": 100,
          "baseline_commit": "legacy-base",
        },
      }) + "\n", encoding="utf-8")

      with mock.patch.object(
        history, "commit_facts", return_value=(commit, "2026-10-01", 1),
      ):
        rows = history.saved(root)

    self.assertEqual(len(rows), 2)
    self.assertIn((commit, "driver-cycles-per-source-line/v0",
                   "legacy-driver-cycles:legacy-base"), rows)
    self.assertNotIn((commit, "driver-cycles-per-source-line/v0",
                      "legacy-driver-cycles:unknown"), rows)
    self.assertIn((commit, history.scaling.METRIC_ID, "base-cpu"), rows)

  def test_metric_and_baseline_rows_remain_distinct(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      commit = "a" * 40
      records = [
        {"metric_id": history.scaling.METRIC_ID, "baseline_id": "base-a"},
        {"metric_id": history.scaling.METRIC_ID, "baseline_id": "base-b"},
        {
          "cycles_per_line": 123.0, "source_lines": 100,
          "baseline_commit": "legacy",
        },
      ]
      (root / "history.jsonl").write_text("\n".join(
        json.dumps({
          "commit": commit, "local_date": "2026-10-02",
          "build_scaling": record,
        }) for record in records
      ) + "\n", encoding="utf-8")
      rows = history.saved(root)
    self.assertEqual(len(rows), 3)
    ids = {key[1:] for key in rows}
    self.assertIn((history.scaling.METRIC_ID, "base-a"), ids)
    self.assertIn((history.scaling.METRIC_ID, "base-b"), ids)
    self.assertIn(
      ("driver-cycles-per-source-line/v0", "legacy-driver-cycles:legacy"),
      ids,
    )


if __name__ == "__main__":
  unittest.main()
