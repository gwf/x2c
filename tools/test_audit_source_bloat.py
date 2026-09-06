from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


TOOLS = pathlib.Path(__file__).resolve().parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location(
    "audit_source_bloat", TOOLS / "audit-source-bloat.py"
)
AUDIT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class AuditTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "src").mkdir()
        (self.root / "lib").mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, path: str, source: str) -> pathlib.Path:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source, encoding="utf-8")
        return target

    def report(self, source: str, path: str = "src/sample.x") -> dict:
        self.write(path, source)
        return AUDIT.analyze(self.root)

    def detector(self, report: dict, name: str) -> dict:
        matches = [item for item in report["findings"]
                   if name in item["detectors"]]
        self.assertTrue(matches, name)
        return matches[0]

    def test_text_report_disclaims_architectural_ranking(self):
        report = self.report("Int value(void) { return 1; }\n")
        self.assertEqual(
            "detector strength only; not architectural value, deletable lines, "
            "or review priority",
            report["score_meaning"],
        )
        json_report = AUDIT.render_json(report)
        self.assertLess(
            json_report.index('"score_meaning"'),
            json_report.index('"findings"'),
        )
        rendered = AUDIT.render_text(report)
        self.assertIn(
            "scores are detector strength, not architectural value or priority",
            rendered,
        )

    def test_ordinal_table_switch_fills_repeated_representation(self):
        cases = "\n".join(
            f"    case TAG_{index}: index = {index};"
            for index in range(8)
        )
        report = self.report(f"""
static const Int rows[] = {{0, 1, 2, 3, 4, 5, 6, 7}};
Int select(Int tag) {{
  Int index;
  switch (tag) {{
{cases}
  }}
  return rows[index];
}}
""")
        finding = self.detector(report, "ordinal-table-switch")
        self.assertEqual(25, finding["components"]["repeated_representation"])
        self.assertEqual(1, finding["components"]["manual_bookkeeping"])

    def test_enum_table_switch_counts_shared_identifiers(self):
        report = self.report("""
enum Role { ROLE_A, ROLE_B, ROLE_C, ROLE_D };
static const Int roles[] = {ROLE_A, ROLE_B, ROLE_C, ROLE_D};
Int role(Int value) {
  switch (value) {
    case ROLE_A: return 1;
    case ROLE_B: return 2;
    case ROLE_C: return 3;
    case ROLE_D: return 4;
  }
  return roles[value];
}
""")
        finding = self.detector(report, "enum-table-switch")
        self.assertEqual(4, finding["raw_counts"]["shared_identifiers"])
        self.assertGreaterEqual(
            finding["components"]["repeated_representation"], 4
        )

    def test_field_and_whole_struct_copy(self):
        report = self.report("""
void copy(Item left, Item right) {
  left.name = right.name;
  left.value = right.value;
  *left = *right;
}
""")
        finding = self.detector(report, "struct-copy")
        self.assertEqual(9, finding["components"]["repeated_representation"])
        self.assertEqual(2, finding["raw_counts"]["same_name_field_transfers"])
        self.assertEqual(1, finding["raw_counts"]["whole_struct_copies"])

    def test_control_blocks_are_not_function_declarations(self):
        report = self.report("""
void choose(Int value) {
  if (value) {
    *left = *right;
  }
  else if (other(value)) {
    *left = *right;
  }
}
""")
        copies = [item for item in report["findings"]
                  if "struct-copy" in item["detectors"]]
        self.assertEqual(1, len(copies))
        self.assertEqual(["choose"], copies[0]["declarations"])

    def test_internal_type_score_and_cap(self):
        members = "\n".join(f"  Int field_{index};" for index in range(40))
        report = self.report(f"struct Private {{\n{members}\n}};\n")
        finding = self.detector(report, "internal-type")
        self.assertEqual(5, finding["components"]["extra_machinery"])
        self.assertEqual(40, finding["raw_counts"]["type_members"])

    def test_type_used_in_another_production_file_is_not_internal(self):
        self.write("src/type.x", "struct Shared { Int value; };\n")
        self.write("src/use.x", "Shared make(void) { Shared value; return value; }\n")
        report = AUDIT.analyze(self.root)
        names = [item["declarations"] for item in report["findings"]
                 if "internal-type" in item["detectors"]]
        self.assertNotIn(["Shared"], names)

    def test_lifecycle_pair(self):
        report = self.report("""
Int Cache.acquire(Int value) { return load(value); }
void Cache.release(Int value) { free(value); }
""")
        finding = self.detector(report, "lifecycle-pair")
        self.assertEqual(2, finding["components"]["extra_machinery"])

    def test_expression_bodies_are_functions(self):
        report = self.report("""
Int Cache.acquire(Int value) => load((Pair) { value, value });
void Cache.release(Int value) => free(value);
""")
        finding = self.detector(report, "lifecycle-pair")
        self.assertEqual(
            ["Cache.acquire", "Cache.release"], finding["declarations"]
        )

    def test_statistics_and_cleanup_bookkeeping(self):
        report = self.report("""
void maintain(State state) {
  state.stats.hits += 1;
  state.stats.misses += 1;
  state.stats.total += 1;
  state.counter += 1;
  state.count += 1;
  free(state.a);
  free(state.b);
  release(state.c);
  close(state.d);
  cleanup(state.e);
}
""")
        finding = self.detector(report, "manual-bookkeeping")
        self.assertEqual(2, finding["components"]["manual_bookkeeping"])
        self.assertEqual(5, finding["raw_counts"]["statistics_sites"])
        self.assertEqual(5, finding["raw_counts"]["cleanup_sites"])

    def test_three_similar_routes(self):
        functions = "\n".join(f"""
Int route_{index}(Int value) {{
  if (ready(value)) {{
    return send(value);
  }}
  return fail(value);
}}
""" for index in range(3))
        finding = self.detector(self.report(functions), "repeated-routes")
        self.assertEqual(3, finding["raw_counts"]["repeated_functions"])
        self.assertEqual(6, finding["components"]["repeated_routes"])

    def test_route_component_is_capped(self):
        functions = "\n".join(f"""
Int route_{index}(Int value) {{
  if (ready(value)) {{
    return send(value);
  }}
  return fail(value);
}}
""" for index in range(10))
        finding = self.detector(self.report(functions), "repeated-routes")
        self.assertEqual(15, finding["components"]["repeated_routes"])

    def test_duplicate_function_bodies_across_files(self):
        body = """
  Int result = prepare(value);
  if (ready(result)) {
    result = send(result);
  }
  return finish(result);
"""
        self.write("src/first.x", f"Int first(Int value) {{{body}}}\n")
        self.write("lib/second.x", f"Int second(Int value) {{{body}}}\n")
        finding = self.detector(
            AUDIT.analyze(self.root), "duplicate-function-body"
        )
        self.assertEqual(2, finding["raw_counts"]["duplicate_functions"])
        self.assertEqual(2, finding["raw_counts"]["duplicate_files"])
        self.assertGreaterEqual(
            finding["components"]["repeated_routes"], 3
        )

    def test_duplicate_function_bodies_in_one_file_are_not_reported(self):
        body = """
  Int result = prepare(value);
  if (ready(result)) {
    result = send(result);
  }
  return finish(result);
"""
        report = self.report(
            f"Int first(Int value) {{{body}}}\n"
            f"Int second(Int value) {{{body}}}\n"
        )
        findings = [
            item for item in report["findings"]
            if "duplicate-function-body" in item["detectors"]
        ]
        self.assertEqual([], findings)

    def test_cosmetic_contributions_and_cap(self):
        prose = "\n".join("// Note that this function is responsible for work."
                           for _ in range(30))
        long_lines = "\n".join("Int value; // " + "x" * 90 for _ in range(12))
        report = self.report(
            prose + "\n\n\n\n" + long_lines + "\n\n\n\nInt final;\n"
        )
        finding = self.detector(report, "cosmetics")
        self.assertEqual(10, finding["components"]["cosmetics"])
        self.assertEqual(2, finding["raw_counts"]["blank_line_runs"])

    def test_nearby_evidence_with_a_common_declaration_merges(self):
        source = AUDIT.Source("src/a.x", "\n" * 100, "\n" * 100)
        left = AUDIT._area("left", source, 0, 10, {"Thing"})
        right = AUDIT._area("right", source, 30, 40, {"Thing"})
        merged = AUDIT._merge_areas([left, right])
        self.assertEqual(1, len(merged))
        self.assertEqual({"left", "right"}, merged[0].detectors)

    def test_nearby_evidence_without_common_declaration_stays_separate(self):
        source = AUDIT.Source("src/a.x", "\n" * 100, "\n" * 100)
        left = AUDIT._area("left", source, 0, 10, {"Left"})
        right = AUDIT._area("right", source, 30, 40, {"Right"})
        self.assertEqual(2, len(AUDIT._merge_areas([left, right])))

    def test_size_versus_use_subtracts_external_calls_and_caps(self):
        body = "\n".join("  value += 1;" for _ in range(800))
        report = self.report(f"""
void Cache.open(Int value) {{
{body}
}}
void Cache.dispose(Int value) {{
{body}
}}
""")
        finding = self.detector(report, "lifecycle-pair")
        self.assertEqual(15, finding["components"]["size_vs_use"])

    def test_stable_identifier_ignores_line_numbers(self):
        first = self.report("""
struct Private {
  Int one;
  Int two;
};
""")
        first_id = self.detector(first, "internal-type")["id"]
        self.write("src/sample.x", "\n\n" + (self.root / "src/sample.x").read_text())
        second = AUDIT.analyze(self.root)
        self.assertEqual(first_id, self.detector(second, "internal-type")["id"])

    def test_input_order_does_not_change_json(self):
        self.write("src/a.x", "struct A { Int value; };\n")
        self.write("lib/b.x", "struct B { Int value; };\n")
        first = AUDIT.render_json(AUDIT.analyze(
            self.root, ["src/a.x", "lib/b.x"]
        ))
        second = AUDIT.render_json(AUDIT.analyze(
            self.root, ["lib/b.x", "src/a.x"]
        ))
        self.assertEqual(first, second)

    def test_generated_library_file_is_excluded(self):
        self.write("src/a.x", "struct A { Int value; };\n")
        self.write("lib/x2c.x", "struct Generated { Int value; };\n")
        report = AUDIT.analyze(self.root)
        self.assertEqual(["src/a.x"], report["paths"])

    def test_json_is_byte_identical_on_repeated_runs(self):
        self.write("src/a.x", "struct A { Int value; };\n")
        first = AUDIT.render_json(AUDIT.analyze(self.root))
        second = AUDIT.render_json(AUDIT.analyze(self.root))
        self.assertEqual(first.encode(), second.encode())

    def test_compare_reports_added_removed_and_changed(self):
        old = self.report("struct Old { Int value; };\n")
        self.write("src/sample.x", "struct New { Int one; Int two; Int three; Int four; };\n")
        new = AUDIT.analyze(self.root)
        result = AUDIT.compare(new, old)
        self.assertEqual(1, len(result["added"]))
        self.assertEqual(1, len(result["removed"]))
        changed_old = json.loads(json.dumps(new))
        changed_old["findings"][0]["score"] -= 1
        result = AUDIT.compare(new, changed_old)
        self.assertEqual(1, len(result["changed"]))

    def test_malformed_inputs_fail_cleanly(self):
        self.write("src/a.x", "struct A { Int value; };\n")
        with self.assertRaisesRegex(ValueError, "does not exist"):
            AUDIT.analyze(self.root, ["missing.x"])
        outside = pathlib.Path(self.temporary.name).parent / "outside.x"
        outside.write_text("", encoding="utf-8")
        try:
            with self.assertRaisesRegex(ValueError, "outside repository"):
                AUDIT.analyze(self.root, [str(outside)])
        finally:
            outside.unlink()
        baseline = {"format_version": 99, "scoring_rule_digest": "bad"}
        with self.assertRaisesRegex(ValueError, "format version"):
            AUDIT.compare(AUDIT.analyze(self.root), baseline)

    def test_command_is_independent_of_working_directory(self):
        command = [sys.executable, str(TOOLS / "audit-source-bloat.py"),
                   "--json", "src/ast.x"]
        root_result = subprocess.run(
            command, cwd=REPO, check=True, capture_output=True
        ).stdout
        other_result = subprocess.run(
            command, cwd=self.root, check=True, capture_output=True
        ).stdout
        self.assertEqual(root_result, other_result)


if __name__ == "__main__":
    unittest.main()
