#!/usr/bin/env python3
"""Exercise the configure entry point and its ordering before core builds."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class ConfigureTests(unittest.TestCase):
  def test_missing_python_compiler_and_archiver_are_reported_together(self):
    with tempfile.TemporaryDirectory() as directory:
      for name in ("make", "cat"):
        Path(directory, name).symlink_to(shutil.which(name))
      result = subprocess.run(
        ["/bin/sh", str(ROOT / "configure")], capture_output=True, text=True,
        env={"PATH": directory},
      )
    self.assertNotEqual(result.returncode, 0)
    for command in ("python3", "cc", "ar"):
      self.assertIn("missing core build tool: " + command, result.stderr)
    self.assertIn("sudo dnf install", result.stderr)

  def test_core_does_not_require_package_tools_or_unused_defaults(self):
    with tempfile.TemporaryDirectory() as directory:
      for name in ("make", "python3", "selected-cc", "selected-ar"):
        Path(directory, name).symlink_to(shutil.which("true"))
      result = subprocess.run(
        ["/bin/sh", str(ROOT / "configure")], capture_output=True, text=True,
        env={"PATH": directory, "CC": "selected-cc", "AR": "selected-ar"},
      )
    self.assertEqual(result.returncode, 0, result.stderr)

  def test_failed_preflight_precedes_bootstrap_and_clean_in_parallel_make(self):
    for target in ("build", "build-safe", "packages"):
      with self.subTest(target=target):
        result = subprocess.run(
          [shutil.which("make"), "-j4", target, "CC=x2c-missing-cc",
           "AR=x2c-missing-ar"], cwd=ROOT, capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing core build tool: x2c-missing-cc", result.stderr)
        self.assertIn("missing core build tool: x2c-missing-ar", result.stderr)
        self.assertNotIn("-C bootstrap", result.stdout)
        self.assertNotIn("-C builds", result.stdout)
        self.assertNotIn("sym-ensure", result.stdout)


if __name__ == "__main__":
  unittest.main()
