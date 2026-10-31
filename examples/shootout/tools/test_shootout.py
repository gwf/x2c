"""Focused checks for mixed reference coverage and source-size accounting."""

import copy
import json
import unittest

import shootout


class ShootoutTests(unittest.TestCase):
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
      original = saved["benchmarks"][name]
      build["benchmarks"][name] = {}
      run["benchmarks"][name] = {"args": original["args"], "implementations": {}}
      for implementation in shootout.X2C_IMPLEMENTATIONS:
        old_key = implementation
        if implementation == "tuned" and "tuned" not in original:
          old_key = "optimized"
        program = original[old_key]
        build["benchmarks"][name][implementation] = {
          "source_metrics": program["source"], **program["build"],
        }
        run["benchmarks"][name]["implementations"][implementation] = program
      for reference in ("rust", "cpp"):
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
    self.assertEqual(row.count("N/A"), 2)


if __name__ == "__main__":
  unittest.main()
