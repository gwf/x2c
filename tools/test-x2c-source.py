#!/usr/bin/env python3
"""Focused checks for source scanning across macro body spellings."""

import unittest

import x2c_source


class MacroSourceTests(unittest.TestCase):
    def names(self, source: str) -> list[str]:
        return [
            definition.name
            for definition in x2c_source.definitions(source, True)
        ]

    def test_statement_scanner_skips_each_macro_body_spelling(self):
        source = """
static int before(void) { return 1; }
macro Statement $direct() {
  if (ready) { use(%{nested: [1, 2]}); }
}
macro Statement $legacy_block() => {
  use(%!() => { return 1; });
}
macro Expression $canonical(Expr $value) =>
  ($value) + use(%!() => { return 1; });
macro Expression $legacy(Expr $value) => ($value + 1)
static int after(void) => 2;
"""
        self.assertEqual(self.names(source), ["before", "after"])

    def test_unit_macro_expands_direct_and_legacy_braced_bodies(self):
        source = """
macro Unit $direct(Name $name) {
  int $name(void) { return 1; }
}
macro Unit $legacy(Name $name) => {
  int $name(void) => 2;
}
$direct(first);
$legacy(second);
"""
        self.assertEqual(self.names(source), ["first", "second"])

    def test_unit_macro_skips_body_generated_name_prefix(self):
        source = """
macro Unit $family(Name $name) {
  using $helper, $label;
  using $cursor;
  int $name(int value) {
    return value;
  }
}
$family(answer);
"""
        definitions = x2c_source.definitions(source, True)
        self.assertEqual([definition.name for definition in definitions],
                         ["answer"])
        self.assertEqual(definitions[0].signature, "int answer(int value)")


if __name__ == "__main__":
    unittest.main()
