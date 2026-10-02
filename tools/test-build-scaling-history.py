#!/usr/bin/env python3
"""Focused tests for build-cost history identity retention."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("build-scaling-history.py")
SPEC = importlib.util.spec_from_file_location("build_scaling_history", SCRIPT)
assert SPEC and SPEC.loader
history = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(history)


class BuildScalingHistoryTests(unittest.TestCase):
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
