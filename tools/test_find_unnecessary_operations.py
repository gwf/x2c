#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import unittest


TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location(
    "find_unnecessary_operations", TOOLS / "find-unnecessary-operations.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class FunctionRangeTest(unittest.TestCase):
    def test_expression_body_balances_nested_braces(self):
        source = (
            "static Pair make(int value) => (Pair) { value, value };\n"
            "int next(int value) => value + 1;\n"
        )
        masked = MODULE.mask_non_code(source)
        ranges = MODULE.function_ranges(masked)
        self.assertEqual(2, len(ranges))
        self.assertEqual(source.index("int next"), ranges[1][0])

    def test_function_pointer_initializer_is_not_a_definition(self):
        source = "int (*callback)(int) = lambda (int value) => value;\n"
        self.assertEqual(
            [], MODULE.function_ranges(MODULE.mask_non_code(source))
        )


if __name__ == "__main__":
    unittest.main()
