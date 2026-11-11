"""Focused source-inventory regression checks; no compiler build required."""
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "repo_metrics", pathlib.Path(__file__).with_name("repo-metrics.py"))
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class SourceInventory(unittest.TestCase):
    def test_nested_modules_and_command_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            files = {
                "src/main.x", "src/parse/expressions/names.x",
                "src/components/match/match.x", "src/components/match/lower.x",
                "commands/build/build.x", "commands/build/module/compile.x",
                "commands/build/tests/fixtures/nested/input.x",
            }
            for name in files:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("int value;\n")
            relative = lambda group: {str(p.relative_to(root))
                for p in metrics.summary_paths(group, files, root)}
            self.assertEqual(relative("src"), {p for p in files if p.startswith("src/")})
            self.assertEqual(relative("components"), {
                "src/components/match/match.x", "src/components/match/lower.x"})
            self.assertEqual(relative("commands"), {
                "commands/build/build.x", "commands/build/module/compile.x"})

    def test_component_subset_not_added_to_total(self):
        source = {name: {"code": 10, "comments": 2}
                  for name in metrics.SUMMARY_GROUPS}
        report = metrics.render_summary({"source": source, "tests": {
            "unit_tests": 0, "compiler_fixtures": 0, "showcase_examples": 0}}, False)
        self.assertIn("total               50        10", report)


if __name__ == "__main__":
    unittest.main()
