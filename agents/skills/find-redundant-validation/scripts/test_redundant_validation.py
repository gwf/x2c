#!/usr/bin/env python3
"""Focused tests for the redundant-validation candidate finder."""

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("redundant_validation.py")
ROOT = SCRIPT.parents[4]
SPEC = importlib.util.spec_from_file_location("redundant_validation", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)
CAUSES = {"alloc-fail", "bad-arg", "malformed", "size-limit"}


def analyze(source, name=None):
    functions = MODULE.extract_functions(source, "src/example.x")
    if name is not None:
        functions = [function for function in functions if function.name == name]
    assert len(functions) == 1, [function.name for function in functions]
    return MODULE.analyze_function(functions[0], CAUSES)


class ExtractionTest(unittest.TestCase):
    def test_extracts_multiline_receiver_function(self):
        source = (
            "static List Compiler.validate_node(\n"
            "  Compiler compiler, List node) {\n"
            "  if (node) { node = node.cdr(); }\n"
            "  return node;\n"
            "}\n"
        )
        function = MODULE.extract_functions(source, "src/example.x")[0]
        self.assertEqual(function.name, "Compiler.validate_node")
        self.assertEqual((function.start, function.end), (1, 5))

    def test_ignores_control_braces_and_literal_text(self):
        source = (
            "void run(void) {\n"
            "  String text = \"report_error(); return nope;\";\n"
            "  if (text) { use(text); }\n"
            "}\n"
        )
        functions = MODULE.extract_functions(source, "src/example.x")
        self.assertEqual([function.name for function in functions], ["run"])

    def test_extracts_expression_body_with_balanced_braces(self):
        source = "static Pair make(int value) => (Pair) { value, value };\n"
        function = MODULE.extract_functions(source, "src/example.x")[0]
        self.assertEqual(function.name, "make")
        self.assertEqual((function.start, function.end), (1, 1))

    def test_does_not_treat_call_before_inner_brace_as_function(self):
        source = (
            "List walk(List p) {\n"
            "  while ((p = p.cdr())) {\n"
            "    use(p);\n"
            "  }\n"
            "  return p;\n"
            "}\n"
        )
        functions = MODULE.extract_functions(source, "src/example.x")
        self.assertEqual([function.name for function in functions], ["walk"])


class ClassificationTest(unittest.TestCase):
    def reasons(self, finding):
        return set() if finding is None else set(finding.reasons)

    def test_flags_return_after_report_error(self):
        finding = analyze(
            "List convert(Compiler compiler, List expr) {\n"
            "  compiler.report_error(<type>, \"bad\", NULL, NULL);\n"
            "  return expr;\n"
            "}\n"
        )
        self.assertIn(
            "return follows non-returning report_error", self.reasons(finding)
        )

    def test_flags_return_after_shared_raise(self):
        finding = analyze(
            "int grow(int size) {\n"
            "  if (size < 0) {\n"
            "    raise %(size-limit (size $size));\n"
            "    return -1;\n"
            "  }\n"
            "  return size;\n"
            "}\n"
        )
        self.assertIn(
            "return follows a non-returning shared Error cause",
            self.reasons(finding),
        )

    def test_does_not_flag_user_defined_resumable_raise(self):
        finding = analyze(
            "int run(void) {\n"
            "  raise %(user-cause);\n"
            "  return -1;\n"
            "}\n"
        )
        self.assertIsNone(finding)

    def test_flags_fresh_literal_null_guard(self):
        finding = analyze(
            "Array copy(void) {\n"
            "  Array result = %[];\n"
            "  if ((void *) result == NULL) return NULL;\n"
            "  return result;\n"
            "}\n"
        )
        self.assertIn(
            "null guard checks a fresh Array or Map literal", self.reasons(finding)
        )

    def test_keeps_null_input_defaulted_to_fresh_map(self):
        finding = analyze(
            "Map collect(Map globs) {\n"
            "  if ((void *) globs == NULL) globs = %{};\n"
            "  return globs;\n"
            "}\n"
        )
        self.assertIsNone(finding)

    def test_flags_growth_confirmation(self):
        finding = analyze(
            "Var push(Array array, Var value) {\n"
            "  size_t expected = array.length + 1;\n"
            "  array.append(&value, 1);\n"
            "  if (array.length != expected) return void;\n"
            "  return value;\n"
            "}\n"
        )
        self.assertIn(
            "checks whether a non-returning growth operation succeeded",
            self.reasons(finding),
        )

    def test_flags_recursive_diagnostic_shape_validator(self):
        finding = analyze(
            "static int _validate_node(Compiler compiler, List node) {\n"
            "  if (node is not <list>) compiler.report_error(<ast>, \"list\", NULL, NULL);\n"
            "  if (node.len() < 2) compiler.report_error(<ast>, \"arity\", NULL, NULL);\n"
            "  if (node.car() == <pair>) return _validate_node(compiler, node.cadr());\n"
            "  return 1;\n"
            "}\n"
        )
        reasons = self.reasons(finding)
        self.assertIn(
            "diagnostics are built around manual List or AST shape checks", reasons
        )
        self.assertIn("diagnostic validator recursively walks its input", reasons)

    def test_recognizes_diagnostic_failure_helper(self):
        finding = analyze(
            "static int _validate_node(List node) {\n"
            "  if (node is not <list>) return _ast_fail();\n"
            "  if (node.len() < 2) return _ast_fail();\n"
            "  if (node.car() != <pair>) return _ast_fail();\n"
            "  return 1;\n"
            "}\n"
        )
        self.assertIn(
            "diagnostics are built around manual List or AST shape checks",
            self.reasons(finding),
        )

    def test_independent_signals_do_not_inflate_one_score(self):
        finding = analyze(
            "static int _validate_node(Compiler compiler, List node) {\n"
            "  if (node is not <list>) compiler.report_error(<ast>, \"list\", NULL, NULL);\n"
            "  if (node.len() < 2) compiler.report_error(<ast>, \"arity\", NULL, NULL);\n"
            "  if (node.car() == <pair>) compiler.report_error(<ast>, \"pair\", NULL, NULL);\n"
            "  return 0;\n"
            "}\n"
        )
        self.assertGreater(len(finding.reasons), 1)
        self.assertEqual(finding.score, 7)

    def test_groups_connected_validator_family_by_size(self):
        source = (
            "static int _validate_child(Compiler compiler, List node) {\n"
            "  if (node is not <list>) compiler.report_error(<ast>, \"list\", NULL, NULL);\n"
            "  if (node.len() < 2) compiler.report_error(<ast>, \"arity\", NULL, NULL);\n"
            "  if (node.car() == <pair>) return _validate_child(compiler, node.cadr());\n"
            "  return 1;\n"
            "}\n"
            "static int _validate_tree(Compiler compiler, List node) {\n"
            "  if (node is not <list>) compiler.report_error(<ast>, \"list\", NULL, NULL);\n"
            "  if (node.len() < 2) compiler.report_error(<ast>, \"arity\", NULL, NULL);\n"
            "  if (node.car() == <pair>) return _validate_child(compiler, node.cadr());\n"
            + "  use(node);\n" * 30
            + "  return 1;\n"
            "}\n"
        )
        functions = MODULE.extract_functions(source, "src/example.x")
        frameworks = MODULE.find_frameworks(functions, CAUSES)
        self.assertEqual(len(frameworks), 1)
        self.assertEqual(
            frameworks[0].functions,
            ("_validate_child", "_validate_tree"),
        )
        self.assertGreaterEqual(frameworks[0].lines, 40)

    def test_recursive_production_walk_is_not_called_a_framework(self):
        source = (
            "static List _transform_node(Compiler compiler, List node) {\n"
            "  if (node is not <list>) compiler.report_error(<ast>, \"list\", NULL, NULL);\n"
            "  if (node.len() < 2) compiler.report_error(<ast>, \"arity\", NULL, NULL);\n"
            "  if (node.car() == <pair>) return _transform_node(compiler, node.cadr());\n"
            + "  emit(node);\n" * 40
            + "  return node;\n"
            "}\n"
        )
        functions = MODULE.extract_functions(source, "src/example.x")
        self.assertEqual(MODULE.find_frameworks(functions, CAUSES), [])

    def test_keeps_external_input_validation(self):
        finding = analyze(
            "static void _validate_cli(Compiler compiler, String path) {\n"
            "  if (!path) compiler.report_error(<input>, \"missing path\", NULL, NULL);\n"
            "}\n"
        )
        self.assertIsNotNone(finding)
        self.assertLess(finding.score, 3)

    def test_keeps_match_based_structural_branch(self):
        finding = analyze(
            "static List _read_node(List node) {\n"
            "  match (node) case %((pair ?left ?right)): return left;\n"
            "  return NULL;\n"
            "}\n"
        )
        self.assertIsNone(finding)

    def test_match_does_not_suppress_manual_shape_checks(self):
        finding = analyze(
            "static List _read_node(List node) {\n"
            "  match (node) case %(pair ?left ?right): return left;\n"
            "  if (node is not <list>) return NULL;\n"
            "  if (node.len() != 3) return NULL;\n"
            "  if (node.car() != <pair>) return NULL;\n"
            "  return node;\n"
            "}\n"
        )
        self.assertIn(
            "manual List or AST shape checks may be one static match",
            self.reasons(finding),
        )


class ProducerConsumerTest(unittest.TestCase):
    def groups(self, source):
        functions = MODULE.extract_functions(source, "src/example.x")
        return MODULE.find_producer_groups(functions)

    def test_groups_silent_guard_under_direct_producer(self):
        groups = self.groups(
            "static void bind_fields(List fields) {\n"
            "  declare_field_order(fields);\n"
            "}\n"
            "static void declare_field_order(List fields) {\n"
            "  foreach (Var value, fields) {\n"
            "    if (value is not <list>) continue;\n"
            "  }\n"
            "}\n"
        )
        group = next(item for item in groups if "bind_fields" in item.shape)
        self.assertEqual(
            [item.name for item in group.consumers], ["declare_field_order"]
        )
        self.assertIn("bind_fields", group.producers[0])

    def test_connects_private_map_reader_to_exact_writer(self):
        groups = self.groups(
            "static void install(Compiler compiler, List row) {\n"
            "  compiler.rows[key] = row;\n"
            "}\n"
            "static void resolve(Compiler compiler) {\n"
            "  while (compiler.rows.try_next(&cursor, &key, &value)) {\n"
            "    if (value is not <list>) continue;\n"
            "  }\n"
            "}\n"
        )
        group = next(item for item in groups if item.shape == "rows registry")
        self.assertEqual(len(group.producers), 1)
        self.assertIn(" install", group.producers[0])

    def test_source_match_is_reported_with_silent_guard(self):
        groups = self.groups(
            "static void consume(List syntax) {\n"
            "  match (syntax) case %(declare ? ?): use(syntax);\n"
            "  foreach (Var value, syntax) {\n"
            "    if (value is not <list>) continue;\n"
            "  }\n"
            "}\n"
        )
        reasons = groups[0].consumers[0].reasons
        self.assertIn(
            "function also recognizes AST with source match", reasons
        )

    def test_partial_state_continue_ranks_first(self):
        groups = self.groups(
            "static List collect(List values) {\n"
            "  Array rows = %[];\n"
            "  foreach (Var value, values) {\n"
            "    if (value is not <list>) continue;\n"
            "    rows.push(value);\n"
            "  }\n"
            "  return rows.list_free();\n"
            "}\n"
        )
        consumer = groups[0].consumers[0]
        self.assertEqual(consumer.score, 6)
        self.assertEqual(consumer.action, "continue with partial state")

    def test_required_historical_calibration(self):
        functions = MODULE.scan_functions(ROOT, ["src"], "2f9e05b9")
        groups = MODULE.find_producer_groups(functions)
        consumers = {
            consumer.name
            for group in groups
            for consumer in group.consumers
        }
        self.assertTrue({
            "SemanticEnvironment.declare_field_order",
            "Emitter.emit_bind",
            "_macro_collect_unit_bindings",
            "Compiler.resolve_protocols",
        }.issubset(consumers))

        field_group = next(
            group for group in groups
            if any(
                item.name == "SemanticEnvironment.declare_field_order"
                for item in group.consumers
            )
        )
        producer_names = "\n".join(field_group.producers)
        self.assertIn("_parse_struct_or_union", producer_names)
        self.assertIn("_bind_syntax_declaration", producer_names)

        protocol_group = next(
            group for group in groups
            if group.shape == "protocol_adoptions registry"
        )
        self.assertEqual(len(protocol_group.producers), 1)
        self.assertIn(
            "_install_protocol_adoption", protocol_group.producers[0]
        )

        self.assertFalse({
            "Ast.try_sequence",
            "Compiler.rebuild_protocols",
            "_transform_cast",
            "_transform_defer_stmt",
            "_transform_return",
        } & consumers)
        self.assertFalse(any(
            name.startswith("_macro_sdk_") for name in consumers
        ))
        self.assertFalse(any(
            name.startswith("_artifact_") for name in consumers
        ))


class StaticMatchCaptureTest(unittest.TestCase):
    def findings(self, source):
        functions = MODULE.extract_functions(source, "src/example.x")
        return MODULE.find_static_match_captures(functions)

    def test_finds_install_declarator_shape(self):
        findings = self.findings(
            "static List install(Var name) {\n"
            "  if (name is <list> && name.list().car() == <marker>) {\n"
            "    List parts = name.list().match(%(marker (?owner) ?member));\n"
            "    Var owner = parts ? parts.assoc(<?owner>) : void;\n"
            "    Var member = parts ? parts.assoc(<?member>) : void;\n"
            "    use(owner, member);\n"
            "  }\n"
            "  return NULL;\n"
            "}\n"
        )
        self.assertEqual([item.name for item in findings], ["install"])
        self.assertEqual(findings[0].assoc_reads, 2)
        self.assertIn(
            "manual List shape checks precede the static match",
            findings[0].reasons,
        )

    def test_ignores_dynamic_and_boolean_only_matches(self):
        findings = self.findings(
            "static void inspect(List value, List pattern) {\n"
            "  List dynamic = value.match(pattern);\n"
            "  use(dynamic.assoc(<?value>));\n"
            "  if (value.match(%(ready *))) use(value);\n"
            "}\n"
        )
        self.assertEqual(findings, [])

    def test_keeps_local_control_and_nested_assoc_use(self):
        findings = self.findings(
            "static void inspect(List value) {\n"
            "  List bindings = value.match(%(node ?child));\n"
            "  if (!bindings) return;\n"
            "  use(bindings.assoc(<?child>));\n"
            "}\n"
        )
        self.assertEqual([item.name for item in findings], ["inspect"])

    def test_ignores_binding_list_that_escapes(self):
        findings = self.findings(
            "static List inspect(List value) {\n"
            "  List bindings = value.match(%(node ?child));\n"
            "  use(bindings.assoc(<?child>));\n"
            "  return bindings;\n"
            "}\n"
        )
        self.assertEqual(findings, [])

    def test_required_install_declarator_calibration(self):
        functions = MODULE.scan_functions(ROOT, ["src/parse.x"], "e3a2b51a")
        findings = MODULE.find_static_match_captures(functions)
        install = [
            item for item in findings if item.name == "_install_declarator"
        ]
        self.assertEqual(len(install), 1)
        self.assertEqual(install[0].assoc_reads, 2)


if __name__ == "__main__":
    unittest.main()
