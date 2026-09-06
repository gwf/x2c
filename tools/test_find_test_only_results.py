#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import tempfile
import unittest


TOOLS = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "find_test_only_results", TOOLS / "find-test-only-results.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class CallScanTest(unittest.TestCase):
    def test_expression_body_declaration_is_not_a_call(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "sample.x"
            path.write_text("int value(int input) =\n> input;\n")
            calls = MODULE.scan([path], {"value": "int"})
        self.assertEqual({}, calls)


if __name__ == "__main__":
    unittest.main()
