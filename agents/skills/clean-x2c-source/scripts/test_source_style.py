#!/usr/bin/env python3

import unittest

from source_style import analyze_text


def categories(path: str, source: str, kind: str) -> list[str]:
    return [finding.category for finding in analyze_text(path, source)
            if finding.kind == kind]


class SourceStyleTest(unittest.TestCase):
    def test_src_forward_declarations_are_violations(self):
        source = "int helper(int value);\n\nint helper(int value) { return value; }\n"
        self.assertIn("forward_declaration", categories("src/unit.x", source, "violation"))

    def test_expression_body_satisfies_forward_declaration(self):
        source = "int helper(int value);\n\nint helper(int value) => value;\n"
        self.assertIn(
            "same_file_forward_declaration",
            categories("lib/unit.x", source, "candidate"),
        )

    def test_lib_same_file_and_cross_unit_declarations_differ(self):
        same = "int helper(int value);\nint helper(int value) { return value; }\n"
        cross = "int other_unit(int value);\n"
        self.assertIn("same_file_forward_declaration",
                      categories("lib/unit.x", same, "candidate"))
        self.assertIn("runtime_forward_declaration",
                      categories("lib/unit.x", cross, "candidate"))

    def test_literals_and_comments_do_not_create_declarations(self):
        source = '// int fake(int value);\nString text = %"int fake(int value);";\n'
        self.assertNotIn("forward_declaration",
                         categories("src/unit.x", source, "violation"))

    def test_wrapped_arguments_start_on_continuation(self):
        source = "void run(void) {\n  call(one,\n    two);\n}\n"
        self.assertIn("wrapped_opening_line", categories("src/unit.x", source, "violation"))

    def test_wrapped_arguments_use_two_spaces(self):
        source = "void run(void) {\n  call(\n      one,\n      two);\n}\n"
        self.assertIn("continuation_indent", categories("src/unit.x", source, "violation"))

    def test_close_stays_with_last_single_line_argument(self):
        source = "void run(void) {\n  call(\n    one,\n    two\n  );\n}\n"
        self.assertIn("standalone_closer", categories("src/unit.x", source, "violation"))

    def test_multiline_argument_permits_standalone_close(self):
        source = "void run(void) {\n  call(\n    %(one\n      two)\n  );\n}\n"
        self.assertNotIn("standalone_closer", categories("src/unit.x", source, "violation"))

    def test_literal_on_closing_line_is_not_standalone(self):
        source = 'void run(void) {\n  call(\n    one,\n    "two");\n}\n'
        self.assertNotIn("standalone_closer",
                         categories("src/unit.x", source, "violation"))

    def test_short_multiline_call_is_a_review_candidate(self):
        source = "void run(void) {\n  call(\n    one,\n    two);\n}\n"
        self.assertIn("horizontal_form", categories("src/unit.x", source, "candidate"))

    def test_multiline_argument_is_not_horizontal_candidate(self):
        source = 'void run(void) {\n  call(\n    %"one\ntwo");\n}\n'
        self.assertNotIn("horizontal_form",
                         categories("src/unit.x", source, "candidate"))

    def test_horizontal_candidate_counts_trailing_expression(self):
        source = ("void run(void) {\n"
                  "  int ok = object.really_long_method_name(\n"
                  "    one, two) >= some_really_long_followup_expression;\n"
                  "}\n")
        self.assertNotIn("horizontal_form",
                         categories("src/unit.x", source, "candidate"))

    def test_mechanical_whitespace_is_reported(self):
        source = "int x = left |  right; \n\n\n\treturn x;\n"
        found = categories("src/unit.x", source, "violation")
        self.assertIn("operator_spacing", found)
        self.assertIn("trailing_whitespace", found)
        self.assertIn("blank_line_stack", found)
        self.assertIn("tab", found)

    def test_table_literal_width_is_a_candidate(self):
        source = '{ "one indivisible literal", <two>, "three indivisible literal that keeps the row stable" },\n'
        self.assertIn("over_width_table_row", categories("lib/unit.x", source, "candidate"))
        self.assertNotIn("over_width", categories("lib/unit.x", source, "violation"))

    def test_deferred_initialization_is_reported(self):
        source = "void run(void) {\n  String value;\n  value = make();\n}\n"
        self.assertIn("deferred_initialization", categories("src/unit.x", source, "violation"))

    def test_one_executable_statement_braces_are_reported(self):
        source = "void run(void) {\n  if (ready) {\n    call();\n  }\n}\n"
        self.assertIn("one_statement_braces", categories("src/unit.x", source, "violation"))

    def test_declaration_body_keeps_braces(self):
        source = "void run(void) {\n  if (ready) {\n    String value = make();\n  }\n}\n"
        self.assertNotIn("one_statement_braces", categories("src/unit.x", source, "violation"))

    def test_dangling_else_body_keeps_braces(self):
        source = ("void run(void) {\n"
                  "  if (outer) {\n"
                  "    if (inner) call();\n"
                  "  }\n"
                  "  else fallback();\n"
                  "}\n")
        self.assertNotIn("one_statement_braces",
                         categories("lib/unit.x", source, "violation"))

    def test_lisp_form_contents_are_not_call_wrapping(self):
        source = ("void run(void) {\n"
                  "  raise %(bad-arg (owner ${\n"
                  "    $(x2c.literal.string (x2c.binding.spelling name))\n"
                  "  }));\n"
                  "}\n")
        self.assertNotIn("wrapped_opening_line",
                         categories("lib/unit.x", source, "violation"))

    def test_repeated_accessor_is_a_review_candidate(self):
        source = "void run(void) {\n  use(node.car());\n  use(node.car());\n  use(node.car());\n}\n"
        self.assertIn("repeated_accessor", categories("src/unit.x", source, "candidate"))

    def test_static_output_run_is_a_review_candidate(self):
        source = 'void help(void) {\n  puts("one");\n  fputs("two\\n", stdout);\n}\n'
        self.assertIn("constant_output_run", categories("src/unit.x", source, "candidate"))


if __name__ == "__main__":
    unittest.main()
