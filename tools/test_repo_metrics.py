from __future__ import annotations

import importlib.util
import pathlib
import re
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
        self.assertIn("37,770", plain)
        self.assertIn("9,245", plain)

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
