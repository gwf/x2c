from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest


TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from x2c_source import (
    Declaration,
    Definition,
    definitions,
    definitions_for_path,
    public_declarations,
    public_declarations_for_path,
)


class DefinitionsTest(unittest.TestCase):
    def test_expression_bodies_are_function_definitions(self):
        source = """typedef struct Counter { int value; } Counter;
typedef int (*Callback)(int);

macro Expression $identity(Expr $value) => ($value)
macro Unit $family(Name $name) => {
  int $name(int value) => value + 1;
}
macro Decorator $keep(Function $function) => {
  $(x2c.function.body $function)...
}

$family(generated);

/** Keeps its documentation through the decorator. */
$keep()
Func decorated(int base) =>
  %!(int value) => {
    return base + value;
  };

static Counter compound(int value) =>
  (Counter) { .value = value };
static Map mapped(int value) => %{<value>: value};
int public_value(int value) => $identity(value);

static int implementation(int value) => value;
static Callback callback = implementation;
static Counter values[count()] = {{0}};
int declared(int value);
"""

        found = definitions(source, include_static=True)

        self.assertEqual(
            ["generated", "decorated", "compound", "mapped",
             "public_value", "implementation"],
            [definition.name for definition in found],
        )
        self.assertEqual(
            "Keeps its documentation through the decorator.", found[1].doc
        )
        self.assertEqual(
            "Func decorated(int base)", found[1].signature
        )

    def test_expression_alias_is_part_of_function_signature(self):
        source = """typedef int tagged;
macro Expression $review.identity(Expr $value) => ($value)
keyword tagged $review.identity;

tagged should_be_found(void) { return 1; }
"""

        self.assertEqual(
            Definition(
                name="should_be_found",
                signature="tagged should_be_found(void)",
                line=5,
                doc=None,
            ),
            definitions(source)[0],
        )

    def test_bare_keyword_decorator_is_not_part_of_signature(self):
        source = """macro Decorator $private.synchronized(
  Function $function
) => {
  $(x2c.function.body $function)...
}

keyword synchronized $private.synchronized;

/** Return the current minimum level. */
synchronized
Symbol Logger.min_level(Logger logger) {
  return logger.min_level;
}
"""

        self.assertEqual(
            Definition(
                name="Logger.min_level",
                signature="Symbol Logger.min_level(Logger logger)",
                line=11,
                doc="Return the current minimum level.",
            ),
            definitions(source)[0],
        )

    def test_lowercase_decorator_remains_visible_to_keyword_aliases(self):
        source = """macro decorator $private.identity(
  function $function
) => {
  $(x2c.function.body $function)...
}

keyword wrapped $private.identity;

wrapped
int lowercase_compatible(void) { return 1; }
"""

        self.assertEqual("lowercase_compatible", definitions(source)[0].name)

    def test_unit_macro_definitions_accept_both_cases(self):
        source = """macro Unit $canonical(Name $name) => {
  int $name(void) { return 1; }
}
macro unit $compatible(name $name) => {
  int $name(void) { return 2; }
}

$canonical(capitalized);
$compatible(lowercase);
"""

        self.assertEqual(
            ["capitalized", "lowercase"],
            [definition.name for definition in definitions(source)],
        )

    def test_imported_unit_macro_propagates_template_doc(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "family.xmacro").write_text(
                """macro Unit $family.method(Name $name) => {
  /** Returns the typed family value. */
  int $name(void) { return 1; }
}
""",
                encoding="utf-8",
            )
            source = root / "consumer.x"
            source.write_text(
                """$(import "family.xmacro")

$family.method(first);
$family.method(second);
""",
                encoding="utf-8",
            )

            definitions = definitions_for_path(source)

        self.assertEqual(["first", "second"], [
            definition.name for definition in definitions
        ])
        self.assertEqual(
            ["Returns the typed family value."] * 2,
            [definition.doc for definition in definitions],
        )


class PublicDeclarationsTest(unittest.TestCase):
    def test_alias_uses_adjacent_doc_but_not_section_comment(self):
        source = """/** A compiler syntax tree. */
typedef List Ast;

/** A detached section comment. */

typedef unsigned long Symbol;
"""

        self.assertEqual(
            (
                Declaration(
                    name="Ast",
                    kind="alias",
                    signature="typedef List Ast",
                    line=2,
                    doc="A compiler syntax tree.",
                ),
                Declaration(
                    name="Symbol",
                    kind="alias",
                    signature="typedef unsigned long Symbol",
                    line=6,
                    doc=None,
                ),
            ),
            public_declarations(source),
        )

    def test_callback_is_distinct_from_ordinary_alias(self):
        source = """/** Receives one emitted diagnostic entry. */
typedef void (*DiagnosticEmitter)(void *owner, List entry);
"""

        self.assertEqual(
            Declaration(
                name="DiagnosticEmitter",
                kind="callback",
                signature=(
                    "typedef void (*DiagnosticEmitter)(void *owner, "
                    "List entry)"
                ),
                line=2,
                doc="Receives one emitted diagnostic entry.",
            ),
            public_declarations(source)[0],
        )

    def test_multiline_aggregate_keeps_nested_field_semicolons(self):
        source = """/** Holds the translation request. */
typedef struct Request {
  int mode;
  union {
    String input;
    File stream;
  } source;
} Request;

/** Names an exit state. */
typedef enum ExitKind {
  EXIT_NONE,
  EXIT_RETURN
} ExitKind;

/** Stores one machine value. */
typedef union MachineValue {
  long integer;
  double floating;
} MachineValue;
"""

        declarations = public_declarations(source)
        self.assertEqual(["Request", "ExitKind", "MachineValue"], [
            declaration.name for declaration in declarations
        ])
        self.assertEqual(["struct", "enum", "union"], [
            declaration.kind for declaration in declarations
        ])
        self.assertEqual(
            "typedef struct Request { int mode; union { String input; "
            "File stream; } source; } Request",
            declarations[0].signature,
        )
        self.assertEqual("Holds the translation request.", declarations[0].doc)
        self.assertEqual(2, declarations[0].line)

    def test_expression_macro_before_aggregate_does_not_hide_it(self):
        source = """typedef struct Lisp *Lisp;

macro Expression $lisp._standard.source() => (
  $(x2c.literal.string "source")
)

/** Counts AUTO activity. */
typedef struct LispAutoStats {
  long invocations, machine_entries, machine_errors;
  long analyses, published, ineligible;
} LispAutoStats;
"""

        self.assertEqual(
            ["Lisp", "LispAutoStats"],
            [declaration.name for declaration in public_declarations(source)],
        )
        self.assertEqual(
            "Counts AUTO activity.", public_declarations(source)[1].doc
        )

    def test_first_private_pragma_ends_public_declarations(self):
        source = """typedef struct Public *Public;

/* #pragma private in a comment does not hide declarations. */
typedef int StillPublic;

#pragma private

typedef int Internal;
#pragma private
typedef int AlsoInternal;
"""

        self.assertEqual(
            ["Public", "StillPublic"],
            [declaration.name for declaration in public_declarations(source)],
        )

    def test_var_abi_assertions_are_excluded(self):
        source = """typedef char x2c_var_abi_byte[(CHAR_BIT == 8) ? 1 : -1];
typedef char x2c_var_abi_signed_char[
  ((signed char) -1 < 0) ? 1 : -1
];
typedef char x2c_string_payload_alignment[
  (sizeof(void *) == 8) ? 1 : -1
];
"""

        self.assertEqual(
            ["x2c_string_payload_alignment"],
            [declaration.name for declaration in public_declarations(source)],
        )

    def test_path_api_reads_one_source(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "types.x"
            path.write_text("typedef int Count;\n", encoding="utf-8")

            self.assertEqual(
                "Count", public_declarations_for_path(path)[0].name
            )


if __name__ == "__main__":
    unittest.main()
