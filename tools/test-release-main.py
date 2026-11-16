#!/usr/bin/env python3
"""Offline checks of tools/release-main against a temporary origin."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("release-main")


class ReleaseMain(unittest.TestCase):
    def git(self, *arguments, cwd=None):
        return subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid",
             *arguments], cwd=cwd or self.work, text=True, capture_output=True,
            check=True).stdout.strip()

    def commit(self, version, message):
        source = self.work / "src/cli/requests.x"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(f'String Compiler.version(void) => "x2c {version}";\n')
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.origin, self.work = root / "origin.git", root / "work"
        self.git("init", "-q", "--bare", "-b", "main", str(self.origin), cwd=root)
        self.git("init", "-q", "-b", "main", str(self.work), cwd=root)
        self.git("remote", "add", "origin", str(self.origin))
        self.released = self.commit("1.2.2", "released")
        self.git("push", "-q", "origin", "main")
        self.git("switch", "-q", "-c", "dev")
        self.selected = self.commit("1.2.3", "selected")
        self.git("push", "-q", "origin", "dev")
        (self.work / "tools").mkdir()
        shutil.copy(SCRIPT, self.work / "tools/release-main")
        # Stands in for the worktree delivery hook, which rejects main.
        hook = self.work / ".git/hooks/pre-push"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)

    def run_tool(self, *arguments):
        return subprocess.run(
            [sys.executable, str(self.work / "tools/release-main"), *arguments],
            text=True, capture_output=True, cwd="/")

    def origin_ref(self, ref):
        result = subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref],
                                cwd=self.origin, text=True, capture_output=True)
        return result.stdout.strip()

    def test_dry_run_pushes_nothing(self):
        run = self.run_tool(self.selected, "1.2.3", "--dry-run")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.origin_ref("main"), self.released)
        self.assertEqual(self.origin_ref("refs/tags/v1.2.3"), "")

    def test_run_publishes_main_and_annotated_tag_once(self):
        run = self.run_tool(self.selected, "1.2.3")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.origin_ref("main"), self.selected)
        self.assertEqual(self.origin_ref("v1.2.3^{commit}"), self.selected)
        self.assertEqual(subprocess.run(
            ["git", "cat-file", "-t", "v1.2.3"], cwd=self.origin, text=True,
            capture_output=True).stdout.strip(), "tag")
        again = self.run_tool(self.selected, "1.2.3")
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIn("nothing to do", again.stdout)

    def test_repeated_run_publishes_only_the_missing_tag(self):
        self.git("push", "-q", "--no-verify", "origin", f"{self.selected}:main")
        run = self.run_tool(self.selected, "1.2.3")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.origin_ref("v1.2.3^{commit}"), self.selected)

    def test_refuses_wrong_version_diverged_main_and_conflicting_tag(self):
        wrong = self.run_tool(self.selected, "1.2.4")
        self.assertIn("does not declare version 1.2.4", wrong.stderr)
        self.git("tag", "-a", "v1.2.3", "-m", "other", self.released)
        self.git("push", "-q", "--no-verify", "origin", "refs/tags/v1.2.3")
        self.git("tag", "-d", "v1.2.3")
        tagged = self.run_tool(self.selected, "1.2.3")
        self.assertIn("origin already has v1.2.3", tagged.stderr)
        self.git("switch", "-q", "main")
        diverged = self.commit("1.2.2", "diverged")
        self.git("push", "-q", "--no-verify", "origin", "main")
        behind = self.run_tool(self.selected, "1.2.3")
        self.assertIn("does not fast-forward", behind.stderr)
        self.assertEqual(self.origin_ref("main"), diverged)
        for run in (wrong, tagged, behind):
            self.assertEqual(run.returncode, 1)


if __name__ == "__main__":
    unittest.main()
