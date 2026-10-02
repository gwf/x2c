#!/usr/bin/env python3
"""Exercise the configure entry point and its ordering before core builds."""

from pathlib import Path
import os
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


class ConfigureHookTests(unittest.TestCase):
  def setUp(self):
    temporary = tempfile.TemporaryDirectory(prefix="x2c-configure-hooks-")
    self.addCleanup(temporary.cleanup)
    self.directory = Path(temporary.name)
    self.root = self.directory / "checkout"
    (self.root / "etc").mkdir(parents=True)
    for name in ("Makefile", "configure", "etc/make-command.mk",
                 "etc/help.mk", "etc/branch.mk", "etc/build-config.mk",
                 "etc/build-mode"):
      shutil.copy2(ROOT / name, self.root / name)
    self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1",
                    GIT_CONFIG_GLOBAL=str(self.directory / "global-config"))

  def command(self, arguments, root=None):
    result = subprocess.run(arguments, cwd=root or self.root, env=self.env,
                            capture_output=True, text=True)
    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    return result

  def test_configure_installs_default_only_when_hooks_path_is_unset(self):
    self.command(["git", "init", "-q"])
    self.command(["make", "configure"])
    self.assertEqual(
      self.command(["git", "config", "--local", "--get",
                    "core.hooksPath"]).stdout.strip(), "tools/hooks")

  def test_configure_preserves_configured_hooks_paths(self):
    self.command(["git", "init", "-q"])
    for scope, hooks in (("--local", "tools/hooks"),
                         ("--local", "custom-hooks"), ("--local", ""),
                         ("--global", "global-hooks")):
      with self.subTest(scope=scope, hooks=hooks):
        self.command(["git", "config", scope, "core.hooksPath", hooks])
        self.command(["make", "configure"])
        configured = self.command(["git", "config", scope, "--get",
                                   "core.hooksPath"]).stdout.rstrip("\n")
        effective = self.command(["git", "config", "--get",
                                  "core.hooksPath"]).stdout.rstrip("\n")
        self.command(["git", "config", scope, "--unset", "core.hooksPath"])
        self.assertEqual(configured, hooks)
        self.assertEqual(effective, hooks)

  def test_configure_preserves_shared_worktree_hooks_path(self):
    self.command(["git", "init", "-q"])
    self.command(["git", "add", "."])
    self.command(["git", "-c", "user.name=Fixture", "-c",
                  "user.email=fixture@example.invalid", "commit", "-qm",
                  "fixture"])
    self.command(["git", "config", "core.hooksPath", "custom-hooks"])
    worktree = self.directory / "linked-worktree"
    self.command(["git", "worktree", "add", "-q", "--detach", str(worktree)])
    self.command(["make", "configure"], root=worktree)
    self.assertEqual(
      self.command(["git", "config", "--get",
                    "core.hooksPath"]).stdout.strip(), "custom-hooks")

  def test_source_archive_configure_needs_no_git_repository(self):
    self.command(["make", "configure"])
    self.assertFalse((self.root / ".git").exists())
    self.assertFalse((self.directory / "global-config").exists())


if __name__ == "__main__":
  unittest.main()
