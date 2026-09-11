#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import tempfile
import unittest


TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location(
    "find_test_only_results", TOOLS / "find-test-only-results.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class CallScanTest(unittest.TestCase):
    def test_calls_after_quoted_symbol_preserve_usage_and_lines(self):
        source = '''String text = "value()";
char letter = 'v';
/* value(); */
// value();
List form = %('symbol);
value(form);
int used = value(form);
'''
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "sample.x"
            path.write_text(source)
            calls = MODULE.scan([path], {"value": "int"})
        self.assertEqual({"value": {
            "discarded": [f"{path}:6"],
            "used": [f"{path}:7"],
        }}, calls)

    def test_expression_body_declaration_is_not_a_call(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "sample.x"
            path.write_text("int value(int input) =\n> input;\n")
            calls = MODULE.scan([path], {"value": "int"})
        self.assertEqual({}, calls)


if __name__ == "__main__":
    unittest.main()
