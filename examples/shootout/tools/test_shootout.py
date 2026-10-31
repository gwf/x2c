"""Focused checks for mixed reference coverage and source-size accounting."""

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import shootout


class ShootoutTests(unittest.TestCase):
  def test_calibration_balances_every_coverage_group(self):
    all_references = {name: {} for name in shootout.REFERENCE_SOURCES.values()}
    sparse = {name: {} for name in ("main.c", "main.py", "main.go", "main.java")}
    benchmarks = [{"references": all_references}, {"references": sparse}]
    self.assertEqual(shootout.calibration_sample_multiple(benchmarks), 24)

  def test_go_raw_strings_preserve_comments_and_whitespace(self):
    source = 'value := `// literal  spaces\n/* literal */\\` // real comment\n'
    clean = shootout.strip_c_comments(source, go=True)
    self.assertNotIn("real comment", clean)
    self.assertIn("// literal  spaces\n/* literal */", clean)
    collapsed = shootout.collapse_code_whitespace(clean, go=True)
    self.assertIn("// literal  spaces\n/* literal */", collapsed)

  def test_python_comments_and_floor_division_are_distinct(self):
    source = """# attribution
def divide(x):
    # implementation comment
    value = x // 2  # trailing comment
    literal = "// and # within a string"
    return value, literal
"""
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      path = root / "program.py"
      path.write_text(source)
      with mock.patch.object(shootout, "ROOT", root), mock.patch.object(
        shootout.gzip, "compress", wraps=shootout.gzip.compress,
      ) as compress:
        result = shootout.source_metrics(path)
    self.assertEqual(result["source_lines"], 4)
    normalized = compress.call_args.args[0]
    self.assertIn(b"x // 2", normalized)
    self.assertIn(b'"// and # within a string"', normalized)
    self.assertNotIn(b"attribution", normalized)
    self.assertNotIn(b"trailing comment", normalized)

  def test_rust_lifetimes_do_not_turn_comments_into_source(self):
    source = """struct Tree<'a> { // node
  child: Option<&'a Tree<'a>>, /* child */
}
let slash = '/'; // character
let literal = "/* keep this */";
"""
    clean = shootout.strip_c_comments(source, rust=True)
    self.assertNotIn("// node", clean)
    self.assertNotIn("/* child */", clean)
    self.assertNotIn("// character", clean)
    self.assertIn("Option<&'a Tree<'a>>", clean)
    self.assertIn('"/* keep this */"', clean)
    collapsed = shootout.collapse_code_whitespace(clean, rust=True)
    self.assertNotIn("\n", collapsed)
    self.assertIn("let slash = '/';", collapsed)

  def test_unavailable_problem_does_not_change_shared_summary(self):
    manifest = shootout.load_manifest()
    baseline = json.loads(shootout.BASELINE_PATH.read_text())
    saved = json.loads(shootout.CURRENT_JSON.read_text())
    build = {"benchmarks": {}}
    run = {key: saved[key] for key in (
      "run_id", "profile", "samples", "warmups", "machine",
    )}
    run["benchmarks"] = {}
    for benchmark in manifest["benchmarks"]:
      name = benchmark["name"]
      if name != "knucleotide":
        for filename in ("main.go", "main.java"):
          benchmark["references"].setdefault(filename, {})
      original = saved["benchmarks"][name]
      build["benchmarks"][name] = {}
      run["benchmarks"][name] = {"args": original["args"], "implementations": {}}
      for implementation in shootout.X2C_IMPLEMENTATIONS:
        program = original[implementation]
        build["benchmarks"][name][implementation] = {
          "source_metrics": program["source"], **program["build"],
        }
        run["benchmarks"][name]["implementations"][implementation] = program
      for reference in ("rust", "cpp", "go", "java"):
        if reference in shootout.available_implementations(benchmark):
          baseline["benchmarks"][name][reference] = copy.deepcopy(
            baseline["benchmarks"][name]["c"]
          )
    first = shootout.make_current(manifest["benchmarks"], baseline, "test", build, run)
    self.assertEqual(len(first["summary_benchmarks"]), 9)
    self.assertNotIn("knucleotide", first["summary_benchmarks"])
    self.assertNotIn("time_rust_over_c", first["benchmarks"]["knucleotide"]["factors"])
    run["benchmarks"]["knucleotide"]["implementations"]["idiomatic"] = copy.deepcopy(
      run["benchmarks"]["knucleotide"]["implementations"]["idiomatic"]
    )
    run["benchmarks"]["knucleotide"]["implementations"]["idiomatic"][
      "statistics"
    ]["median_elapsed_ns"] *= 1000000
    second = shootout.make_current(manifest["benchmarks"], baseline, "test", build, run)
    self.assertEqual(first["median"], second["median"])
    self.assertEqual(first["arithmetic_mean"], second["arithmetic_mean"])
    text = shootout.render_current(second)
    row = next(line for line in text.splitlines() if line.startswith("| knucleotide |"))
    missing = len(shootout.IMPLEMENTATIONS) - len(shootout.available_implementations(
      next(b for b in manifest["benchmarks"] if b["name"] == "knucleotide")
    ))
    self.assertEqual(row.count("N/A"), missing)


if __name__ == "__main__":
  unittest.main()
