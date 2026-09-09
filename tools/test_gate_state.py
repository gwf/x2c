#!/usr/bin/env python3
"""Focused tests for publication gate reuse and recording."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


TOOLS = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    assert spec.loader
    spec.loader.exec_module(module)
    return module


GATE_STATE = load("gate_state", TOOLS / "gate-state.py")


class EnsureTests(unittest.TestCase):
    def test_valid_record_is_reused_without_running_gate(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check", return_value=0),
            mock.patch.object(GATE_STATE, "run_gate") as run_gate,
            mock.patch.object(GATE_STATE, "cmd_record") as record,
        ):
            result = GATE_STATE.cmd_ensure("doc-check")

        self.assertEqual(result, 0)
        run_gate.assert_not_called()
        record.assert_not_called()

    def test_stale_record_runs_corresponding_make_target(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check", return_value=1),
            mock.patch.object(GATE_STATE, "run_gate", return_value=0) as run_gate,
            mock.patch.object(GATE_STATE, "cmd_record", return_value=0),
        ):
            result = GATE_STATE.cmd_ensure("agent-pr-check")

        self.assertEqual(result, 0)
        run_gate.assert_called_once_with("agent-pr-check")

    def test_successful_gate_records_resulting_tree(self):
        before = {
            "version": GATE_STATE.FORMAT,
            "files": {"tracked": "before"},
            "configuration": {"test": "cc"},
            "recorded_at_head": "abc",
        }
        after = {**before, "files": {"tracked": "after"}}
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "gate-state.json"
            with (
                mock.patch.object(GATE_STATE, "STATE", state),
                mock.patch.object(
                    GATE_STATE, "digest", side_effect=[before, after]
                ),
                mock.patch.object(
                    GATE_STATE, "run_gate", return_value=0
                ) as run_gate,
                mock.patch("sys.stdout", new_callable=io.StringIO),
            ):
                result = GATE_STATE.cmd_ensure("doc-check")

            records = json.loads(state.read_text())

        self.assertEqual(result, 0)
        run_gate.assert_called_once_with("doc-check")
        self.assertEqual(records["doc-check"], after)

    def test_unknown_gate_is_rejected(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check") as check,
            mock.patch.object(GATE_STATE, "run_gate") as run_gate,
            mock.patch.object(GATE_STATE, "cmd_record") as record,
            mock.patch("sys.stderr", new_callable=io.StringIO) as stderr,
        ):
            result = GATE_STATE.cmd_ensure("check")

        self.assertEqual(result, 2)
        self.assertIn("unknown gate 'check'", stderr.getvalue())
        check.assert_not_called()
        run_gate.assert_not_called()
        record.assert_not_called()

    def test_failed_gate_returns_status_without_recording(self):
        with (
            mock.patch.object(GATE_STATE, "cmd_check", return_value=1),
            mock.patch.object(GATE_STATE, "run_gate", return_value=7),
            mock.patch.object(GATE_STATE, "cmd_record") as record,
        ):
            result = GATE_STATE.cmd_ensure("doc-check")

        self.assertEqual(result, 7)
        record.assert_not_called()

    def test_gate_output_is_inherited_live(self):
        completed = mock.Mock(returncode=0)
        with mock.patch.object(
            GATE_STATE.subprocess, "run", return_value=completed
        ) as run:
            result = GATE_STATE.run_gate("doc-check")

        self.assertEqual(result, 0)
        run.assert_called_once_with(
            ["make", "doc-check"], cwd=GATE_STATE.ROOT, check=False
        )


class ExistingCommandTests(unittest.TestCase):
    def test_record_and_check_still_store_and_reuse_any_named_gate(self):
        stamp = {
            "version": GATE_STATE.FORMAT,
            "files": {"tracked": "1234"},
            "configuration": {"test": "cc"},
            "recorded_at_head": "abc",
        }
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch.object(
                GATE_STATE, "STATE", Path(directory) / "gate-state.json"
            ),
            mock.patch.object(GATE_STATE, "digest", return_value=stamp),
            mock.patch("sys.stdout", new_callable=io.StringIO),
        ):
            self.assertEqual(GATE_STATE.cmd_record("custom-gate"), 0)
            self.assertEqual(GATE_STATE.cmd_check("custom-gate"), 0)


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="x2c-config-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.object(GATE_STATE, "ROOT", self.root))
        stack.enter_context(mock.patch.dict(os.environ, {
            "BUILD_MODE": "optimize", "BUILD_LTO": "0", "MAKEFLAGS": "",
            "MFLAGS": "",
        }))
        (self.root / "etc").mkdir()
        shutil.copy2(TOOLS.parent / "etc/build-config.mk", self.root / "etc")
        (self.root / "etc/build-mode").write_text("optimize\n")
        (self.root / "Makefile").write_text(
            "include etc/build-config.mk\ndoc-check: ;\n"
        )

    def test_make_precedence_and_derived_flags_are_used(self):
        before = GATE_STATE.build_configuration()
        with mock.patch.dict(os.environ, {"BUILD_MODE": "debug", "BUILD_LTO": "1"}):
            after = GATE_STATE.build_configuration()
        self.assertNotEqual(before, after)
        self.assertIn("-O2", before["values"]["BUILD_CFLAGS"])
        self.assertIn("-g", after["values"]["BUILD_CFLAGS"])
        self.assertIn("-flto", after["values"]["BUILD_LDFLAGS"])
        self.assertEqual(before, GATE_STATE.build_configuration())
        with mock.patch.dict(os.environ, {
            "BUILD_MODE": "debug", "MAKEFLAGS": "BUILD_MODE=optimize",
        }):
            values = GATE_STATE.make_configuration()
        self.assertEqual(values["BUILD_MODE"], "optimize")
        self.assertIn("-O2", values["BUILD_CFLAGS"])

    def test_flags_search_paths_and_command_overrides_affect_configuration(self):
        before = GATE_STATE.build_configuration()
        for name, value in {
            "CFLAGS": "-O1 -DVALUE=2",
            "EXTRA_CFLAGS": "-fno-strict-aliasing",
            "X2C_FLAGS": "--jobs 2",
            "CPATH": "/test/include",
            "MAKEFLAGS": "CHILD_ONLY=value",
        }.items():
            with self.subTest(name=name), mock.patch.dict(os.environ, {name: value}):
                self.assertNotEqual(before, GATE_STATE.build_configuration())
        with mock.patch.dict(os.environ, {"UNRELATED_SESSION_ID": "other"}):
            self.assertEqual(before, GATE_STATE.build_configuration())

    def test_selected_compiler_and_same_version_content_changes_are_detected(self):
        # Keep version output fixed to exercise replacement without a version
        # bump. The inert fixture must never execute a copied system launcher.
        compiler = self.root / "compiler"
        compiler.write_bytes(b"inert compiler identity fixture\n")
        compiler.chmod(0o755)
        run = subprocess.run
        def inspect(arguments, **kwargs):
            if arguments == [str(compiler.resolve()), "--version"]:
                return subprocess.CompletedProcess(
                    arguments, 0, "same version\n", ""
                )
            return run(arguments, **kwargs)
        with mock.patch.dict(os.environ, {"CC": str(compiler)}), mock.patch.object(
            GATE_STATE.subprocess, "run", side_effect=inspect
        ):
            before = GATE_STATE.build_configuration()
            with compiler.open("ab") as output:
                output.write(b"gate identity probe\n")
            after = GATE_STATE.build_configuration()
        self.assertEqual(before["tools"]["CC"]["version"],
                         after["tools"]["CC"]["version"])
        self.assertNotEqual(before["tools"]["CC"]["sha256"],
                            after["tools"]["CC"]["sha256"])
        self.assertNotEqual(before, GATE_STATE.build_configuration())

    def test_missing_compiler_and_opaque_wrappers_cannot_be_inspected(self):
        wrapper = self.root / "wrapper"
        wrapper.write_text("#!/bin/sh\nexec cc \"$@\"\n")
        wrapper.chmod(0o755)
        for command in ("/missing/cc", "ccache cc", str(wrapper)):
            with self.subTest(command=command), mock.patch.dict(
                os.environ, {"CC": command}
            ), self.assertRaises(ValueError):
                GATE_STATE.build_configuration()

    def test_recursive_make_replacement_changes_configuration(self):
        recursive_make = self.root / "recursive-make"
        recursive_make.write_bytes(b"inert recursive make version one\n")
        recursive_make.chmod(0o755)
        with mock.patch.dict(os.environ, {
            "MAKEFLAGS": f"MAKE={recursive_make}",
        }):
            before = GATE_STATE.build_configuration()
            recursive_make.write_bytes(b"inert recursive make version two\n")
            after = GATE_STATE.build_configuration()
        self.assertEqual(before["tools"]["make"], after["tools"]["make"])
        self.assertEqual(before["tools"]["MAKE"]["path"],
                         str(recursive_make.resolve()))
        self.assertNotEqual(before, after)

    @unittest.skipUnless(sys.platform == "darwin", "Apple developer tools")
    def test_apple_identity_tracks_delegated_executable_not_launcher(self):
        compiler = self.root / "selected-clang"
        compiler.write_bytes(b"inert selected compiler\n")
        def inspect(arguments, **kwargs):
            if arguments == ["/usr/bin/xcrun", "--find", "cc"]:
                return subprocess.CompletedProcess(
                    arguments, 0, str(compiler) + "\n", ""
                )
            self.assertEqual(arguments, [str(compiler.resolve()), "--version"])
            return subprocess.CompletedProcess(arguments, 0, "same version\n", "")
        with mock.patch.object(GATE_STATE.subprocess, "run", side_effect=inspect):
            before = GATE_STATE.tool_identity("/usr/bin/cc", os.environ["PATH"], True)
            compiler.write_bytes(b"replaced selected compiler\n")
            after = GATE_STATE.tool_identity("/usr/bin/cc", os.environ["PATH"], True)
        self.assertEqual(before["path"], str(compiler.resolve()))
        self.assertEqual(before["version"], after["version"])
        self.assertNotEqual(before["sha256"], after["sha256"])

    @unittest.skipUnless(sys.platform == "darwin", "Apple developer tools")
    def test_effective_tool_environment_reaches_resolver_without_reselecting_make(self):
        compiler = self.root / "selected-clang"
        compiler.write_bytes(b"inert selected compiler\n")
        make_path = self.root / "make"
        make_path.write_bytes(b"inert make identity\n")
        values = dict.fromkeys(GATE_STATE.CONFIG_VARIABLES, "")
        values.update({
            "MAKE": str(make_path), "CC": "cc", "AR": "ar",
            "PATH": "/effective/tool/path",
            "DEVELOPER_DIR": "/effective/developer", "TOOLCHAINS": "selected",
        })
        def which(name, path):
            if name == "make":
                self.assertEqual(path, os.environ["PATH"])
                return str(make_path)
            self.assertEqual(path, values["PATH"])
            if name == str(make_path):
                return str(make_path)
            return "/usr/bin/cc" if name == "cc" else str(compiler)
        def inspect(arguments, **kwargs):
            self.assertEqual(kwargs["env"]["DEVELOPER_DIR"], values["DEVELOPER_DIR"])
            self.assertEqual(kwargs["env"]["TOOLCHAINS"], "selected")
            if arguments == ["/usr/bin/xcrun", "--find", "cc"]:
                return subprocess.CompletedProcess(
                    arguments, 0, str(compiler) + "\n", ""
                )
            self.assertEqual(arguments, [str(compiler.resolve()), "--version"])
            return subprocess.CompletedProcess(arguments, 0, "same version\n", "")
        with (
            mock.patch.object(GATE_STATE, "make_configuration", return_value=values),
            mock.patch.object(GATE_STATE.shutil, "which", side_effect=which),
            mock.patch.object(GATE_STATE.subprocess, "run", side_effect=inspect) as run,
        ):
            GATE_STATE.build_configuration()
        self.assertEqual(run.call_count, 2)

    def test_modes_that_skip_work_or_errors_cannot_produce_evidence(self):
        for flags in ("n", "t", "q", "i", "--dry-run", "--ignore-errors"):
            with self.subTest(flags=flags), mock.patch.dict(
                os.environ, {"MAKEFLAGS": flags}
            ), self.assertRaises(ValueError):
                GATE_STATE.make_configuration()

    def test_inspection_does_not_execute_default_recipes(self):
        with (self.root / "Makefile").open("a") as makefile:
            makefile.write(
                "default:\n\t@touch must-not-exist\n"
                ".DEFAULT_GOAL := default\n"
            )
        GATE_STATE.build_configuration()
        self.assertFalse((self.root / "must-not-exist").exists())


class TreeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="x2c-gate-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.object(GATE_STATE, "ROOT", self.root))
        stack.enter_context(mock.patch.object(
            GATE_STATE, "STATE", self.root / "debug/gate-state.json"
        ))
        stack.enter_context(mock.patch("sys.stdout", new_callable=io.StringIO))
        self.git("init", "-q")
        self.git("config", "user.name", "Gate Test")
        self.git("config", "user.email", "gate@example.invalid")
        self.git("config", "core.filemode", "true")
        self.git("config", "core.autocrlf", "false")
        (self.root / ".gitignore").write_text("debug/\n")
        (self.root / "Makefile").write_text("doc-check: ;\n")
        (self.root / "input").write_text("one\n")
        (self.root / "run.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.root / "run.sh").chmod(0o755)
        (self.root / "link").symlink_to("input")
        self.commit()

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, check=True, capture_output=True,
            text=True,
        ).stdout

    def commit(self):
        self.git("add", "-A")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "snapshot")

    def record(self):
        self.assertEqual(GATE_STATE.cmd_record("doc-check"), 0)

    def valid(self):
        self.assertEqual(GATE_STATE.cmd_check("doc-check"), 0)

    def stale(self):
        self.assertEqual(GATE_STATE.cmd_check("doc-check"), 1)

    def test_content_changes_and_staging_or_commit_without_changes(self):
        self.record()
        (self.root / "input").write_text("two\n")
        self.stale()
        self.record()
        self.git("add", "input")
        self.valid()
        self.commit()
        self.valid()

    def test_executable_changes_even_when_git_ignores_filemode(self):
        self.record()
        path = self.root / "run.sh"
        path.chmod(0o644)
        self.stale()
        self.record()
        self.git("add", "run.sh")
        self.valid()
        self.git("config", "core.filemode", "false")
        path.chmod(0o755)
        self.stale()

    def test_symlink_target_bytes_and_type_are_distinct(self):
        (self.root / "other").write_text("one\n")
        self.commit()
        self.record()
        link = self.root / "link"
        link.unlink()
        link.symlink_to("other")
        self.stale()
        self.record()
        self.git("add", "link")
        self.valid()
        link.unlink()
        link.write_text("other")
        self.stale()
        self.record()
        self.git("add", "link")
        self.valid()

    def test_dangling_symlinks_survive_staging_and_target_creation(self):
        path = self.root / "dangling"
        path.symlink_to("debug/missing")
        self.record()
        self.git("add", "dangling")
        self.valid()
        (self.root / "debug/missing").write_text("ignored target\n")
        self.valid()
        path.unlink()
        path.symlink_to("debug/different")
        self.stale()

    def test_deletions_and_new_files_survive_staging(self):
        self.record()
        (self.root / "input").unlink()
        self.stale()
        self.record()
        self.git("add", "-A")
        self.valid()
        self.commit()
        self.valid()
        (self.root / "new").write_text("new\n")
        self.stale()
        self.record()
        self.git("add", "new")
        self.valid()

    def test_ignored_files_do_not_invalidate(self):
        self.record()
        (self.root / "debug/log").write_text("output\n")
        self.valid()

    def test_old_records_are_unknown(self):
        self.record()
        records = GATE_STATE.load()
        records["doc-check"]["version"] = GATE_STATE.FORMAT - 1
        GATE_STATE.save(records)
        self.stale()

    def test_clean_files_reuse_index_content_hashes(self):
        with mock.patch.object(
            GATE_STATE, "content_hash", wraps=GATE_STATE.content_hash
        ) as content_hash:
            GATE_STATE.digest()
        content_hash.assert_not_called()

    def install_cli(self):
        (self.root / "tools").mkdir()
        script = self.root / "tools/gate-state.py"
        shutil.copy2(TOOLS / "gate-state.py", script)
        return script

    def test_failed_git_inventory_cannot_record_or_reuse(self):
        script = self.install_cli()
        self.record()
        before = GATE_STATE.STATE.read_bytes()
        (self.root / ".git").rename(self.root / ".git-unavailable")
        for command in ("check", "record", "ensure"):
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, str(script), command, "doc-check"],
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("valid -", result.stdout)
                self.assertEqual(GATE_STATE.STATE.read_bytes(), before)

    def test_ensure_runs_make_only_when_needed_and_never_records_failure(self):
        script = self.install_cli()
        (self.root / "Makefile").write_text(
            "doc-check:\n"
            "\t@mkdir -p debug\n"
            "\t@cat input >> debug/executions\n"
            "\t@test ! -e fail\n"
        )
        self.commit()
        def ensure():
            return subprocess.run(
                [sys.executable, str(script), "ensure", "doc-check"],
                capture_output=True, text=True,
            )
        self.assertEqual(ensure().returncode, 0)
        self.assertEqual(ensure().returncode, 0)
        runs = self.root / "debug/executions"
        self.assertEqual(runs.read_text(), "one\n")
        (self.root / "run.sh").chmod(0o644)
        self.assertEqual(ensure().returncode, 0)
        self.assertEqual(runs.read_text(), "one\none\n")
        before = GATE_STATE.STATE.read_bytes()
        (self.root / "fail").touch()
        self.assertNotEqual(ensure().returncode, 0)
        self.assertEqual(GATE_STATE.STATE.read_bytes(), before)
        self.stale()


if __name__ == "__main__":
    unittest.main()
