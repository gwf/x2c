#!/usr/bin/env python3
"""Focused tests for the performance snapshot collector."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("performance-snapshot.py")
SPEC = importlib.util.spec_from_file_location("performance_snapshot", SCRIPT)
assert SPEC and SPEC.loader
snapshot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(snapshot)


class PerformanceSnapshotTests(unittest.TestCase):
  def test_command_order_builds_stage_three_only_once(self):
    names = [name for name, _ in snapshot.COMMANDS]
    self.assertEqual(
      names,
      ["setup", "stage-3", "stage-diff", "build-scaling", "shootout",
       "runtime", "compiler"],
    )
    flattened = [argument for _, command in snapshot.COMMANDS
                 for argument in command]
    self.assertNotIn("stage-diff-all", flattened)
    self.assertEqual(flattened.count("stage-3"), 1)

  def test_compiler_summary_groups_medians_by_stage_and_mode(self):
    content = "\n".join([
      "make noise",
      "benchmark,stage,mode,sample,seconds,bytes,sha256",
      "translation,stage-0,default,1,3.0,1,a",
      "translation,stage-0,default,2,1.0,1,a",
      "translation,stage-0,default,3,2.0,1,a",
      "translation,stage-1,live,1,4.0,1,b",
      "translation,stage-1,live,2,6.0,1,b",
    ])
    with tempfile.TemporaryDirectory() as directory:
      path = Path(directory) / "compiler.log"
      path.write_text(content, encoding="utf-8")
      result = snapshot.compiler_summary(path)
    self.assertEqual(result, {"stage-0/default": 2.0, "stage-1/live": 5.0})

  def test_runtime_summary_preserves_distinct_output_shapes(self):
    content = "\n".join([
      "x2c-performance-target,bm-list",
      "sample,1",
      "list-get,3.0",
      "sample,2",
      "list-get,1.0",
      "x2c-performance-target,bm-iter",
      "iter-next,5.0",
      "iter-next,7.0",
      "x2c-performance-target,bm-logger",
      "optimized-sample,1",
      "logger-write,2.0",
      "x2c-performance-target,bm-varops",
      "optimized,1,i32-fast,4.0",
    ])
    with tempfile.TemporaryDirectory() as directory:
      path = Path(directory) / "runtime.log"
      path.write_text(content, encoding="utf-8")
      result = snapshot.runtime_summary(path)
    self.assertEqual(len(result["records"]), 6)
    medians = {
      (row["target"], row["mode"], row["metric"]): row["median"]
      for row in result["medians"]
    }
    self.assertEqual(medians[("bm-list", None, "list-get")], 2.0)
    self.assertEqual(medians[("bm-iter", None, "iter-next")], 6.0)
    self.assertEqual(
      medians[("bm-logger", "optimized", "logger-write")], 2.0,
    )
    self.assertEqual(medians[("bm-varops", "optimized", "i32-fast")], 4.0)

  def test_successful_today_ignores_failures_and_malformed_rows(self):
    with tempfile.TemporaryDirectory() as directory:
      path = Path(directory) / "history.jsonl"
      path.write_text(
        "not json\n"
        + json.dumps({
          "local_date": "2026-09-21", "status": "success",
        }) + "\n"
        + json.dumps({
          "local_date": "2026-09-21", "status": "failed",
        }) + "\n",
        encoding="utf-8",
      )
      self.assertTrue(snapshot.successful_today(path, "2026-09-21"))
      self.assertFalse(snapshot.successful_today(path, "2026-09-22"))

  def test_atomic_json_replaces_complete_document(self):
    with tempfile.TemporaryDirectory() as directory:
      path = Path(directory) / "latest.json"
      snapshot.atomic_json(path, {"status": "success"})
      self.assertEqual(json.loads(path.read_text()), {"status": "success"})
      self.assertEqual(list(Path(directory).glob("*.tmp-*")), [])

  def test_report_compares_headline_and_worst_runtime_change(self):
    previous = {
      "run_id": "old", "commit": "a", "status": "success",
      "stage_3_seconds": 10.0,
      "build_scaling": {"score": 100.0},
      "compiler_median_seconds": {"stage-0/default": 2.0},
      "runtime_medians": [{
        "target": "bm-list", "mode": None, "metric": "get",
        "median": 4.0,
      }],
    }
    current = {
      "run_id": "new", "commit": "b", "status": "success",
      "stage_3_seconds": 11.0,
      "build_scaling": {"score": 106.0},
      "compiler_median_seconds": {"stage-0/default": 1.0},
      "runtime_medians": [{
        "target": "bm-list", "mode": None, "metric": "get",
        "median": 5.0,
      }],
    }
    report = snapshot.render_report(current, previous)
    self.assertIn("stage-3 seconds | 10 | 11 | +10.00%", report)
    self.assertIn("build cost score | 100 | 106 | +6.00%", report)
    self.assertIn(
      "- Build cost score: 106.0 (+6.0)\n", report,
    )
    self.assertIn("compiler stage-0/default seconds | 2 | 1 | -50.00%", report)
    self.assertIn("runtime bm-list/get | 4 | 5 | +25.00%", report)

  def test_failed_logged_command_retains_output_and_status(self):
    with tempfile.TemporaryDirectory() as directory:
      result = snapshot.run_logged(
        "failure", [sys.executable, "-c", "print('kept'); raise SystemExit(7)"],
        Path(directory), os.environ.copy(), 10,
      )
      self.assertEqual(result["returncode"], 7)
      self.assertFalse(result["timed_out"])
      self.assertEqual(
        (Path(directory) / "failure.log").read_text(), "kept\n",
      )

  def test_logged_command_times_out_its_process_group(self):
    with tempfile.TemporaryDirectory() as directory:
      result = snapshot.run_logged(
        "timeout", [sys.executable, "-c", "import time; time.sleep(60)"],
        Path(directory), os.environ.copy(), 1,
      )
    self.assertTrue(result["timed_out"])
    self.assertNotEqual(result["returncode"], 0)


if __name__ == "__main__":
  unittest.main()
