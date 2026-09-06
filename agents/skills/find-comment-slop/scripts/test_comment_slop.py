#!/usr/bin/env python3
"""Focused tests for the x2c comment candidate finder."""

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("comment_slop.py")
SPEC = importlib.util.spec_from_file_location("comment_slop", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CommentExtractionTest(unittest.TestCase):
    def test_ignores_comment_openers_in_quotes(self):
        source = 'String a = %"// no";\nchar *b = "/* no */";\n// yes\n'
        comments = MODULE.extract_comments(source, "src/example.x")
        self.assertEqual([comment.text for comment in comments], ["yes"])

    def test_groups_adjacent_line_comments(self):
        source = "// first\n// second\nint value;\n"
        comments = MODULE.extract_comments(source, "src/example.x")
        self.assertEqual(len(comments), 1)
        self.assertEqual(comments[0].text, "first\nsecond")


class ClassificationTest(unittest.TestCase):
    def classify(self, source, path="src/example.x", tier=None):
        tiers = {path: tier} if tier else {}
        return MODULE.classify_file(path, source, tiers)

    def reasons(self, result):
        return {reason for item in result.candidates for reason in item.reasons}

    def test_flags_short_function_narration(self):
        result = self.classify(
            "// Parse one list element.\n"
            "static List _parse_list_element(Compiler compiler) {\n"
            "  return NULL;\n"
            "}\n"
        )
        self.assertIn("restates the following function name", self.reasons(result))

    def test_flags_expression_function_narration(self):
        result = self.classify(
            "// Parse one list element.\n"
            "static List _parse_list_element(Compiler compiler) => NULL;\n"
        )
        self.assertIn("restates the following function name", self.reasons(result))

    def test_keeps_comment_that_states_invariant(self):
        result = self.classify(
            "// void terminates protocols and is never Array data.\n"
            "static int _require_array_value(Var value) {\n"
            "  return !value.is_void();\n"
            "}\n"
        )
        self.assertNotIn("restates the following function name", self.reasons(result))

    def test_flags_statement_narration(self):
        result = self.classify(
            "void f(void) {\n"
            "  // Release the String pool.\n"
            "  String.pool_release();\n"
            "}\n"
        )
        self.assertIn("translates the following statement", self.reasons(result))

    def test_accepts_compact_public_doc(self):
        result = self.classify(
            "/** Returns the number of elements in `array`. */\n"
            "size_t Array.len(Array array) {\n"
            "  return array.length;\n"
            "}\n",
            path="lib/array.x",
            tier="api",
        )
        self.assertEqual(result.candidates, [])

    def test_accepts_readable_blank_after_doc_summary(self):
        result = self.classify(
            "/** Returns the number of elements.\n"
            "\n"
            "    This operation has constant cost.\n"
            "*/\n"
            "size_t Array.len(Array array) { return array.length; }\n",
            path="lib/array.x",
            tier="api",
        )
        self.assertEqual(result.candidates, [])

    def test_accepts_real_doc_paragraph_after_substantial_prose(self):
        result = self.classify(
            "/** Returns the value stored under `key`, or `void` when absent.\n"
            "    This is a compatibility surface. The result is unambiguous\n"
            "    because `void` cannot be stored in the Map.\n"
            "\n"
            "    Raises: `<void-op>` when `key` is `void`.\n"
            "*/\n"
            "Var Map.get(Map map, Var key) { return void; }\n",
            path="lib/map.x",
            tier="api",
        )
        self.assertEqual(result.candidates, [])

    def test_accepts_short_later_doc_paragraph(self):
        result = self.classify(
            "/** Returns a new Map in the current scope. Every call allocates,\n"
            "    so two results are distinct even when both are empty.\n"
            "\n"
            "    The table starts with two slots.\n"
            "\n"
            "    Keys and values may be heterogeneous.\n"
            "*/\n"
            "Map Map.new(void) { return NULL; }\n",
            path="lib/map.x",
            tier="api",
        )
        self.assertEqual(result.candidates, [])

    def test_flags_doc_on_static_helper(self):
        result = self.classify(
            "/** Finds the next item. */\n"
            "static int _next(void) { return 0; }\n",
            path="lib/iter.x",
            tier="api",
        )
        self.assertIn("public doc comment on a private static helper", self.reasons(result))

    def test_flags_doc_in_internal_module(self):
        result = self.classify(
            "/** Reads one token. */\n"
            "Token Tokenizer.next(Tokenizer tokenizer) { return NULL; }\n",
            path="lib/tokenizer.x",
            tier="internal",
        )
        self.assertIn("doc comment in internal library module", self.reasons(result))

    def test_does_not_treat_public_doc_length_as_removable(self):
        prose = " ".join(["observable behavior remains documented"] * 35)
        result = self.classify(
            f"/** Returns a documented value. {prose}. */\n"
            "Value Value.read(Value value) { return value; }\n",
            path="lib/value.x",
            tier="api",
        )
        self.assertFalse(
            any("more than" in reason for reason in self.reasons(result))
        )

    def test_duplicate_paragraph_counts_only_the_duplicate_lines(self):
        result = self.classify(
            "/** Reads a value.\n\n"
            "    Shared behavior remains visible\n"
            "    to every public caller. */\n"
            "Value Value.read(Value value) { return value; }\n"
            "/** Writes a value.\n\n"
            "    Shared behavior remains visible\n"
            "    to every public caller. */\n"
            "Value Value.write(Value value) { return value; }\n",
            path="lib/value.x",
            tier="api",
        )
        duplicates = [
            item for item in result.candidates
            if "repeats prose elsewhere in the file" in item.reasons
        ]
        self.assertEqual(len(duplicates), 2)
        self.assertEqual([item.removable_lines for item in duplicates], [2, 2])

    def test_flags_stacked_doc_comments(self):
        result = self.classify(
            "/** First summary. */\n"
            "/** Second summary. */\n"
            "int public_function(void) { return 0; }\n",
            path="lib/example.x",
            tier="api",
        )
        self.assertIn("stacked doc comment is detached from a definition", self.reasons(result))

    def test_bloat_ranking_is_independent_of_violation_ranking(self):
        violation = MODULE.FileResult("src/a.x", 10, 1, 10, 1, 20, [])
        bloat = MODULE.FileResult("lib/b.x", 1, 30, 1, 3, 40, [])
        self.assertEqual(
            MODULE.rank_results([violation, bloat], "violations")[0].path,
            "src/a.x",
        )
        self.assertEqual(
            MODULE.rank_results([violation, bloat], "bloat")[0].path,
            "lib/b.x",
        )


if __name__ == "__main__":
    unittest.main()
