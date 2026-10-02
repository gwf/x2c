#!/usr/bin/env python3
"""Focused tests for the optional build-cost measurement."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("build-scaling.py")
SPEC = importlib.util.spec_from_file_location("build_scaling", SCRIPT)
assert SPEC and SPEC.loader
scaling = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scaling)


class BuildScalingTests(unittest.TestCase):
  def test_authored_and_generated_source_counts_are_separate(self):
    with tempfile.TemporaryDirectory() as directory:
      tree = Path(directory)
      for name in ("src", "lib"):
        (tree / name).mkdir()
      (tree / "src/author.x").write_text("a\nb\n", encoding="utf-8")
      (tree / "src/linked-meta.x").write_text("g\ng\ng\n", encoding="utf-8")
      (tree / "lib/hand.xmacro").write_text("m\n", encoding="utf-8")
      (tree / "lib/x2c.x").write_text("g\ng\n", encoding="utf-8")
      (tree / "lib/ignored.txt").write_text("x\n", encoding="utf-8")
      self.assertEqual(scaling.source_lines(tree), {
        "authored_source_lines": 3,
        "generated_source_lines": 5,
        "total_source_lines": 8,
      })

  def test_child_cpu_includes_grandchild_work(self):
    grandchild = (
      "import time; end=time.process_time()+0.20; n=0; "
      "exec('while time.process_time()<end: n+=1')"
    )
    child = (
      "import subprocess,sys; "
      f"subprocess.run([sys.executable,'-c',{grandchild!r}],check=True)"
    )
    with tempfile.TemporaryDirectory() as directory:
      seconds = scaling.run_make(
        [sys.executable, "-c", child], Path(directory), {},
      )
    self.assertGreater(seconds, 0.15)

  def test_legacy_baseline_is_rejected_before_building(self):
    with tempfile.TemporaryDirectory() as directory:
      baseline = Path(directory) / "baseline.json"
      baseline.write_text(
        '{"commit":"old", "cycles_per_line":1}', encoding="utf-8",
      )
      arguments = [str(SCRIPT), "--compiler", "/usr/bin/true"]
      with mock.patch.object(scaling, "BASELINE", baseline), \
           mock.patch.object(scaling, "measure") as measure, \
           mock.patch.object(sys, "argv", arguments):
        with self.assertRaisesRegex(ValueError, "explicitly rebaseline"):
          scaling.main()
      measure.assert_not_called()


if __name__ == "__main__":
  unittest.main()
