#!/usr/bin/env python3
"""Focused tests for the performance snapshot collector."""

import importlib.util
import contextlib
import io
import json
import os
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace


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
      "build_scaling": {
        "score": 100.0, "metric_id": "cpu/v1", "baseline_id": "base-a",
      },
      "compiler_median_seconds": {"stage-0/default": 2.0},
      "runtime_medians": [{
        "target": "bm-list", "mode": None, "metric": "get",
        "median": 4.0,
      }],
    }
    current = {
      "run_id": "new", "commit": "b", "status": "success",
      "stage_3_seconds": 11.0,
      "build_scaling": {
        "score": 106.0, "metric_id": "cpu/v1", "baseline_id": "base-a",
      },
      "compiler_median_seconds": {"stage-0/default": 1.0},
      "runtime_medians": [{
        "target": "bm-list", "mode": None, "metric": "get",
        "median": 5.0,
      }],
    }
    report = snapshot.render_report(current, previous)
    self.assertIn("stage-3 seconds | 10 | 11 | +10.00%", report)
    self.assertIn(
      "build cost score [cpu/v1 @ base-a] | 100 | 106 | +6.00%", report,
    )
    self.assertIn(
      "- build cost score [cpu/v1 @ base-a]: 106.0 (+6.0)\n", report,
    )
    self.assertIn("compiler stage-0/default seconds | 2 | 1 | -50.00%", report)
    self.assertIn("runtime bm-list/get | 4 | 5 | +25.00%", report)

  def test_build_cost_scores_with_different_identities_are_not_compared(self):
    previous = {
      "run_id": "old", "commit": "a", "status": "success",
      "build_scaling": {
        "score": 100.0, "metric_id": "cycles/v0", "baseline_id": "base-a",
      },
    }
    current = {
      "run_id": "new", "commit": "b", "status": "success",
      "build_scaling": {
        "score": 100.0, "metric_id": "cpu/v1", "baseline_id": "base-b",
      },
    }
    report = snapshot.render_report(current, previous)
    self.assertIn("build cost score [cpu/v1 @ base-b]: 100.0", report)
    self.assertNotIn("(+0.0)", report)

  def test_legacy_build_cost_without_identity_is_not_compared(self):
    row = {"build_scaling": {"score": 100.0}}
    self.assertEqual(snapshot.comparable_metrics(row), {})

  def test_absolute_cpu_rows_require_compatible_metric_identities(self):
    previous = {"run_id": "old", "commit": "a", "status": "success",
                "build_scaling": {"cpu_seconds": 12.0,
                                  "metric_id": "cpu/v1", "baseline_id": "a"}}
    current = {"run_id": "new", "commit": "b", "status": "success",
               "build_scaling": {"cpu_seconds": 9.0,
                                 "metric_id": "cpu/v2", "baseline_id": "a"}}
    report = snapshot.render_report(current, previous)
    self.assertIn("sequential stage build CPU seconds | n/a | 9 | n/a", report)
    current["build_scaling"]["metric_id"] = "cpu/v1"
    report = snapshot.render_report(current, previous)
    self.assertIn("sequential stage build CPU seconds | 12 | 9 | -25.00%", report)

  def test_first_report_keeps_absolute_measurements_and_workload(self):
    current = {
      "run_id": "first", "commit": "a", "status": "success",
      "stage_3_seconds": 40.0,
      "compiler_median_seconds": {"stage-0/default": 3.0},
      "build_scaling": {"cpu_seconds": 9.0,
                        "cpu_seconds_per_authored_line": 0.003},
    }
    report = snapshot.render_report(current, None)
    self.assertIn("first successful retained snapshot", report)
    self.assertIn("stage-3 seconds | n/a | 40 | n/a", report)
    self.assertIn("compiler stage-0/default seconds | n/a | 3", report)
    self.assertIn("sequential stage build CPU seconds | n/a | 9", report)
    self.assertIn("CPU seconds/authored line | n/a | 0.003", report)
    self.assertIn("not native compilation or a full compiler translation", report)
    self.assertNotIn("instruction", report)

  def test_report_includes_new_measurements_without_old_values(self):
    old = {"run_id": "old", "commit": "a", "status": "success"}
    new = {"run_id": "new", "commit": "b", "status": "success",
           "compiler_median_seconds": {"stage-0/default": 3.0}}
    self.assertIn("seconds | n/a | 3 | n/a", snapshot.render_report(new, old))

  @contextlib.contextmanager
  def snapshot_checkout(self, child_status=0):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      repository = root / "repository"
      repository.mkdir()
      script = repository / "tools/performance-snapshot.py"
      script.parent.mkdir()
      script.write_text(
        "from pathlib import Path\nimport sys\n"
        "tree = Path.cwd()\n"
        "(tree / 'compiler').write_text('reproduction compiler')\n"
        "(tree / 'generated.c').write_text('reproduction output')\n"
        "output = Path(sys.argv[sys.argv.index('--output-root') + 1])\n"
        "output.mkdir(parents=True, exist_ok=True)\n"
        "(output / 'summary.json').write_text('existing summary')\n"
        "(output / 'setup.log').write_text('existing log')\n"
        f"raise SystemExit({child_status})\n", encoding="utf-8",
      )
      def command(*args):
        subprocess.run(["git", *args], cwd=repository, check=True,
                       capture_output=True)
      command("init", "-q")
      command("add", ".")
      command("-c", "user.name=Snapshot Test", "-c",
              "user.email=snapshot@example.invalid", "commit", "-qm", "seed")
      temporary = root / "temporary"
      temporary.mkdir()
      args = SimpleNamespace(fetch=False, ref="HEAD", step_timeout=1,
                             skip_if_success_today=False)
      output = root / "history"
      with mock.patch.object(snapshot, "ROOT", repository), \
          mock.patch.object(snapshot.tempfile, "mkdtemp",
                            return_value=str(temporary)):
        yield args, output, temporary
      if (temporary / "worktree/.git").exists():
        command("worktree", "remove", "--force", str(temporary / "worktree"))

  def test_successful_ref_cleans_worktree_but_keeps_history(self):
    with self.snapshot_checkout() as (args, output, temporary):
      self.assertEqual(snapshot.run_ref(args, output), 0)
      self.assertFalse(temporary.exists())
      self.assertEqual((output / "summary.json").read_text(), "existing summary")
      self.assertEqual((output / "setup.log").read_text(), "existing log")

  def test_failed_ref_retains_compiler_generated_output_and_history(self):
    with self.snapshot_checkout(7) as (args, output, temporary):
      message = io.StringIO()
      with contextlib.redirect_stderr(message):
        self.assertEqual(snapshot.run_ref(args, output), 7)
      worktree = temporary / "worktree"
      self.assertTrue((worktree / ".git").exists())
      self.assertEqual((worktree / "compiler").read_text(),
                       "reproduction compiler")
      self.assertTrue((worktree / "generated.c").exists())
      self.assertEqual((output / "setup.log").read_text(), "existing log")
      self.assertIn(f"retained worktree: {worktree}", message.getvalue())

  def test_cancelled_child_retains_worktree_and_existing_receipts(self):
    kill_self = "__import__('os').kill(__import__('os').getpid(), 15)"
    with self.snapshot_checkout(kill_self) as (args, output, temporary):
      message = io.StringIO()
      with contextlib.redirect_stderr(message):
        self.assertEqual(snapshot.run_ref(args, output), -15)
      self.assertTrue((temporary / "worktree/compiler").exists())
      self.assertEqual((output / "summary.json").read_text(), "existing summary")
      self.assertIn(str(temporary / "worktree"), message.getvalue())

  def test_failed_cleanup_preserves_successful_child_worktree(self):
    with self.snapshot_checkout() as (args, output, temporary):
      run = subprocess.run
      def fail_remove(command, **kwargs):
        if command[:3] == ["git", "worktree", "remove"]:
          return subprocess.CompletedProcess(command, 1)
        return run(command, **kwargs)
      message = io.StringIO()
      with mock.patch.object(snapshot.subprocess, "run", fail_remove), \
          contextlib.redirect_stderr(message):
        self.assertEqual(snapshot.run_ref(args, output), 0)
      self.assertTrue((temporary / "worktree/compiler").exists())
      self.assertIn("cleanup failed; retained worktree", message.getvalue())

  def test_exception_and_cancellation_retain_created_worktree(self):
    for error in (OSError("cannot launch child"), KeyboardInterrupt()):
      with self.subTest(error=type(error).__name__), \
          self.snapshot_checkout() as (args, output, temporary):
        run = subprocess.run
        def interrupt_child(command, **kwargs):
          if command[0] == sys.executable:
            raise error
          return run(command, **kwargs)
        message = io.StringIO()
        with mock.patch.object(snapshot.subprocess, "run", interrupt_child), \
            contextlib.redirect_stderr(message):
          with self.assertRaises(type(error)):
            snapshot.run_ref(args, output)
        self.assertTrue((temporary / "worktree/.git").exists())
        self.assertIn(str(temporary / "worktree"), message.getvalue())

  def test_setup_failure_cleans_unused_directory_and_reports_separately(self):
    with self.snapshot_checkout() as (args, output, temporary):
      args.ref = "missing-snapshot-reference"
      message = io.StringIO()
      with contextlib.redirect_stderr(message):
        with self.assertRaises(subprocess.CalledProcessError):
          snapshot.run_ref(args, output)
      self.assertFalse(temporary.exists())
      self.assertFalse(output.exists())
      self.assertIn("setup failed before worktree creation", message.getvalue())
      self.assertNotIn("retained worktree", message.getvalue())

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
