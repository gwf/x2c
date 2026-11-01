"""Focused checks for mixed reference coverage and source-size accounting."""

import argparse
import base64
import copy
import hashlib
import importlib.util
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
    build = {"benchmarks": {}}
    run = {"run_id": "synthetic", "profile": "local", "samples": 1,
           "warmups": 0, "machine": baseline["calibration"]["machine"]}
    run["benchmarks"] = {}
    for benchmark in manifest["benchmarks"]:
      name = benchmark["name"]
      if name != "knucleotide":
        for filename in ("main.go", "main.java"):
          benchmark["references"].setdefault(filename, {})
      original = baseline["benchmarks"][name]
      build["benchmarks"][name] = {}
      run["benchmarks"][name] = {"args": original["args"], "implementations": {}}
      for implementation in shootout.X2C_IMPLEMENTATIONS:
        program = {"statistics": original["c"]["statistics"], "measurements": []}
        build["benchmarks"][name][implementation] = {
          "source_metrics": original["c"]["source"], "binary_bytes": 1,
          "binary_sha256": "test", "compile_ns": 1, "translate_ns": 1,
          "generated_c_sha256": "test",
        }
        run["benchmarks"][name]["implementations"][implementation] = program
      for reference in ("rust", "cpp", "go", "java"):
        if reference in shootout.available_implementations(benchmark):
          baseline["benchmarks"][name][reference] = copy.deepcopy(
            baseline["benchmarks"][name]["c"]
          )
    baseline["benchmarks"]["binarytrees"].pop("python", None)
    first = shootout.make_current(manifest["benchmarks"], baseline, "test", build, run)
    self.assertEqual(len(first["summary_benchmarks"]), 8)
    self.assertNotIn("binarytrees", first["summary_benchmarks"])
    self.assertNotIn("sloc_c_over_python", first["benchmarks"]["binarytrees"]["factors"])
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

  def test_promoted_results_survive_scratch_build_cleanup(self):
    json_path = shootout.CURRENT_JSON.relative_to(shootout.REPO)
    markdown_path = shootout.CURRENT_MARKDOWN.relative_to(shootout.REPO)
    with tempfile.TemporaryDirectory() as directory:
      repo = Path(directory)
      current_json, current_markdown = repo / json_path, repo / markdown_path
      build = repo / shootout.BUILD.relative_to(shootout.REPO)
      def compile_measure(argv):
        Path(argv[-1]).write_bytes(b"measure")
      with mock.patch.multiple(shootout, BUILD=build,
                               CURRENT_JSON=current_json,
                               CURRENT_MARKDOWN=current_markdown), \
           mock.patch.object(shootout, "render_current", return_value="report\n"), \
           mock.patch.object(shootout, "command", side_effect=compile_measure):
        shootout.promote_current({"run_id": "preserved"})
        chart = current_json.parent / "charts" / "runtime-source-size.svg"
        chart.parent.mkdir(parents=True)
        chart.write_text("chart\n")
        build.mkdir(parents=True, exist_ok=True)
        (build / "stale-output").write_text("scratch")
        shootout.prepare_build({"cc": "cc"})
        self.assertEqual(json.loads(current_json.read_text())["run_id"], "preserved")
        self.assertEqual(current_markdown.read_text(), "report\n")
        self.assertEqual(chart.read_text(), "chart\n")
        self.assertFalse((build / "stale-output").exists())


class CompactBaselineTests(unittest.TestCase):
  @classmethod
  def setUpClass(cls):
    path = shootout.REPO / "examples/shootout-unofficial/tools/shootout.py"
    spec = importlib.util.spec_from_file_location("unofficial_shootout", path)
    legacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    cls.harnesses = (shootout, legacy)

  def test_tracked_baselines_load_without_historical_results(self):
    for harness in self.harnesses:
      with self.subTest(suite=harness.ROOT.name):
        saved = json.loads(harness.BASELINE_PATH.read_text())
        baseline = harness.load_baseline(harness.load_manifest(), saved["methodology"])
        self.assertEqual(baseline, saved)
        for entry in baseline["benchmarks"].values():
          self.assertEqual("stdout" in entry, entry["comparison"]["kind"] != "exact")
          self.assertFalse(any(isinstance(value, dict) and "measurements" in value
                               for value in entry.values()))

  def test_exact_hash_and_numeric_tolerance(self):
    for harness in self.harnesses:
      with self.subTest(suite=harness.ROOT.name):
        exact = {"comparison": {"kind": "exact"},
                 "stdout_sha256": hashlib.sha256(b"exact\n").hexdigest()}
        harness.compare_pinned_output("test", "x2c", exact, b"exact\n")
        with self.assertRaises(harness.HarnessError):
          harness.compare_pinned_output("test", "x2c", exact, b"wrong\n")
        numeric = {"args": [], "comparison": {"kind": "numeric_lines",
                   "absolute_tolerance": 1e-8},
                   "stdout": base64.b64encode(b"1.000000000\n").decode()}
        harness.compare_pinned_output("test", "x2c", numeric, b"1.000000001\n")
        for output in (b"1.000000020\n", b"1.0\n"):
          with self.assertRaises(harness.HarnessError):
            harness.compare_pinned_output("test", "x2c", numeric, output)

  def test_calibration_writes_statistics_without_raw_reference_samples(self):
    for harness in self.harnesses:
      with self.subTest(suite=harness.ROOT.name):
        manifest = harness.load_manifest()
        saved = json.loads(harness.BASELINE_PATH.read_text())
        build = {"toolchain": saved["methodology"], "benchmarks": {}}
        calibration = {"run_id": "synthetic", "machine": saved["calibration"]["machine"],
                       "benchmarks": {}}
        for benchmark in manifest["benchmarks"]:
          name = benchmark["name"]
          entry = copy.deepcopy(saved["benchmarks"][name])
          implementations = {key: value for key, value in entry.items()
                             if isinstance(value, dict) and "statistics" in value}
          build["benchmarks"][name] = {key: {"source_metrics": value["source"]}
                                      for key, value in implementations.items()}
          for value in implementations.values():
            del value["source"]
            value["measurements"] = [{"elapsed_ns": 1}]
          entry["implementations"] = implementations
          entry.setdefault("stdout", base64.b64encode(b"exact\n").decode())
          calibration["benchmarks"][name] = entry
        result = harness.make_baseline(manifest, manifest["benchmarks"], build,
                  calibration, argparse.Namespace(profile="local", samples=1, warmups=0))
        self.assertEqual(result["benchmarks"], saved["benchmarks"])


if __name__ == "__main__":
  unittest.main()
