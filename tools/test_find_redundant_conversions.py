#!/usr/bin/env python3

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location(
    "find_redundant_conversions", TOOLS / "find-redundant-conversions.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class ConversionScanTest(unittest.TestCase):
    def test_quoted_symbol_discovery_keeps_translation_proof_and_offsets(self):
        source = '''String text = "value.integer()";
char letter = 'v';
/* value.integer(); */
// value.pointer();
List form = %('symbol);
int used = value.integer();
void *native = value.pointer();
'''
        observed = []

        def translate(root, compiler, relative):
            current = (root / relative).read_text()
            observed.append(current)
            # Only the integer conversion has identical generated output.
            output = ("same" if "void *native = value.pointer();" in current
                      else "different")
            return subprocess.CompletedProcess([], 0, output, "")

        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            relative = pathlib.Path("sample.x")
            (root / relative).write_text(source)
            with patch.object(MODULE, "translate", side_effect=translate):
                results, failed = MODULE.audit(
                    root, pathlib.Path("unused"), [relative],
                    {"integer", "pointer"},
                )
            self.assertEqual(source, (root / relative).read_text())
        integer = source.index(".integer()", source.index("int used"))
        pointer = source.index(".pointer()", source.index("void *native"))
        self.assertEqual([
            source,
            source[:integer] + source[integer + len(".integer()"):],
            source[:pointer] + source[pointer + len(".pointer()"):],
        ], observed)
        self.assertEqual({}, failed)
        self.assertEqual([{
            "file": "sample.x", "line": 6, "method": "integer",
            "kind": "declaration", "start": integer,
            "end": integer + len(".integer()"),
            "text": "int used = value.integer();",
        }], results)


if __name__ == "__main__":
    unittest.main()
