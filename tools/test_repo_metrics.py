from __future__ import annotations

import importlib.util
import io
import json
import pathlib
import re
import shutil
import sys
import tempfile
import types
import unittest
from unittest import mock


TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
SCRIPT = TOOLS / "repo-metrics.py"
SPEC = importlib.util.spec_from_file_location("repo_metrics", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ClocTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("cloc"), "cloc is not installed")
    def test_lisp_and_macro_comment_syntax(self):
        sources = {
            "xlisp": '''// Lisp comment
/* a block
   comment */

(def quoted 'name) // trailing comment
(def url "https://example.test/*literal*/")
(def text '"// not a comment")
(def answer 42)
''',
            "xmacro": '''// Macro comment
/* a block
   comment */

macro Expression $answer() => (
  $(list 'expr nil (list 'literal '(int) "42")) // embedded Lisp
)
macro Expression $text() => ("/* string, not comment */")
''',
        }
        with tempfile.TemporaryDirectory() as directory:
            for extension, source in sources.items():
                with self.subTest(extension=extension):
                    path = pathlib.Path(directory) / f"source.{extension}"
                    path.write_text(source)
                    self.assertEqual(
                        {"code": 4, "comments": 3},
                        MODULE.cloc_lines([path]),
                    )

    def test_parses_summary_row(self):
        output = """files,language,blank,comment,code,version
27,C,1724,2740,22395,cloc
27,SUM,1724,2740,22395,cloc
"""

        self.assertEqual(
            {"code": 22395, "comments": 2740},
            MODULE.parse_cloc(output),
        )

    def test_missing_cloc_is_reported(self):
        with mock.patch.object(
            MODULE.subprocess, "run", side_effect=FileNotFoundError
        ):
            with self.assertRaisesRegex(MODULE.Fatal, "cloc is required"):
                MODULE.cloc_lines([pathlib.Path("one.x")])

    def test_failed_cloc_is_reported(self):
        result = types.SimpleNamespace(
            returncode=2, stdout="", stderr="unsupported option"
        )
        with mock.patch.object(MODULE.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(MODULE.Fatal, "unsupported option"):
                MODULE.cloc_lines([pathlib.Path("one.x")])


class InventoryTest(unittest.TestCase):
    def test_core_sources_are_disjoint_and_exclude_generated_lisp(self):
        paths = {
            "src/compiler.x", "lib/runtime.x", "lib/x2c.x",
            "src/helpers.xlisp", "lib/helpers.xlisp", "etc/helpers.xlisp",
            "src/helpers.xmacro", "lib/helpers.xmacro", "etc/helpers.xmacro",
            "etc/symbols.xlisp", "etc/header-symbols.xlisp",
            "etc/vsc-extension/test/editor.xlisp",
            "packages/adapter/src/helpers.xmacro",
            "examples/helpers.xlisp", "unittest/helpers.xmacro",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in paths:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("// source\n")
            groups = {
                name: {path.relative_to(root).as_posix() for path in
                       MODULE.source_paths(patterns, root)}
                for name, patterns in MODULE.SUMMARY_GROUPS.items()
            }
            self.assertEqual({
                "src": {"src/compiler.x"},
                "lib": {"lib/runtime.x", "lib/x2c.x"},
                "xlisp": {"src/helpers.xlisp", "lib/helpers.xlisp",
                          "etc/helpers.xlisp"},
                "xmacro": {"src/helpers.xmacro", "lib/helpers.xmacro",
                           "etc/helpers.xmacro"},
            }, groups)

    def test_counts_only_real_test_registrations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            tests = root / "unittest"
            tests.mkdir()
            (tests / "test-one.x").write_text(
                """void suite(void) {
  $test.run(first);
  TestHarness_run("second", second);
  TestHarness_skip("later", "not ready");
  // $test.run(commented_out);
  String text = "$test.run(not_a_test);";
}
""",
                encoding="utf-8",
            )
            (tests / "test-all.x").write_text(
                "$test.run(driver_noise);\n", encoding="utf-8"
            )
            (tests / "test-support.x").write_text(
                "void TestHarness_run(const char *name, TestFn fn) {}\n",
                encoding="utf-8",
            )

            self.assertEqual(3, MODULE.unit_tests(root))

    def test_counts_fixture_and_showcase_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            fixtures = root / "unittest" / "compiler-fixtures"
            fixtures.mkdir(parents=True)
            (fixtures / "one.phases").write_text("status\n")
            (fixtures / "two.phases").write_text("stdout\n")
            (fixtures / "two.x").write_text("int main(void) {}\n")
            examples = root / "examples"
            examples.mkdir()
            (examples / "manifest.txt").write_text(
                """# name|category|check|arguments|stdout|note
one|showcase|run||-|one
two|probe|run||-|two
three|showcase|build||-|three
""",
                encoding="utf-8",
            )

            self.assertEqual(2, MODULE.compiler_fixtures(root))
            self.assertEqual(2, MODULE.showcase_examples(root))


class RenderTest(unittest.TestCase):
    RECORD = {
        "source": {
            "src": {"code": 22395, "comments": 2740},
            "lib": {"code": 15375, "comments": 6505},
            "xlisp": {"code": 569, "comments": 35},
            "xmacro": {"code": 2448, "comments": 523},
        },
        "tests": {
            "unit_tests": 721,
            "compiler_fixtures": 549,
            "showcase_examples": 32,
        },
    }

    def test_color_changes_only_presentation(self):
        plain = MODULE.render_summary(self.RECORD, color=False)
        colored = MODULE.render_summary(self.RECORD, color=True)
        stripped = re.sub(r"\x1b\[[0-9;]*m", "", colored)

        self.assertEqual(plain, stripped)
        self.assertNotIn("\x1b", plain)
        self.assertIn("\x1b", colored)
        self.assertIn("40,787", plain)
        self.assertIn("9,803", plain)
        self.assertIn("X Lisp", plain)
        self.assertIn("X macros", plain)

    def test_summary_json_uses_summary_collector(self):
        output = io.StringIO()
        with mock.patch.object(
            sys, "argv", [str(SCRIPT), "--summary-json"]
        ), mock.patch.object(
            MODULE, "collect_summary", return_value=self.RECORD
        ), mock.patch.object(sys, "stdout", output):
            self.assertEqual(0, MODULE.main())
        self.assertEqual(self.RECORD, json.loads(output.getvalue()))

    def test_auto_color_honors_terminal_environment(self):
        terminal = mock.Mock()
        terminal.isatty.return_value = True
        redirected = mock.Mock()
        redirected.isatty.return_value = False

        self.assertTrue(MODULE.color_enabled("always", redirected, {}))
        self.assertFalse(MODULE.color_enabled("never", terminal, {}))
        self.assertTrue(MODULE.color_enabled("auto", terminal, {}))
        self.assertFalse(
            MODULE.color_enabled("auto", terminal, {"NO_COLOR": "1"})
        )
        self.assertFalse(
            MODULE.color_enabled("auto", terminal, {"TERM": "dumb"})
        )
        self.assertFalse(MODULE.color_enabled("auto", redirected, {}))


if __name__ == "__main__":
    unittest.main()
