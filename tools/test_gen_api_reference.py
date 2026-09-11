from __future__ import annotations

import importlib.util
import io
import pathlib
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from unittest import mock


TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
SCRIPT = TOOLS / "gen-api-reference.py"
SPEC = importlib.util.spec_from_file_location("gen_api_reference", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class DocSectionsTest(unittest.TestCase):
    def test_first_sentence_does_not_need_a_paragraph_break(self):
        doc = "Returns `a...b` unchanged. A second sentence follows directly."
        self.assertEqual(MODULE.first_sentence(doc),
                         "Returns `a...b` unchanged.")

    def test_raises_does_not_need_a_blank_line(self):
        tight = "Returns a value.\nRaises: `<bad-arg>` for zero."
        spaced = "Returns a value.\n\nRaises: `<bad-arg>` for zero."
        expected = (
            (None, "Returns a value."),
            ("Raises", "`<bad-arg>` for zero."),
        )
        self.assertEqual(MODULE.doc_sections(tight), expected)
        self.assertEqual(MODULE.doc_sections(spaced), expected)

    def test_preserves_readability_paragraphs(self):
        doc = (
            "Returns a value.\n\n"
            "The second paragraph explains ownership.\n"
            "Raises: `<bad-arg>` for zero."
        )
        self.assertEqual(
            MODULE.doc_sections(doc),
            (
                (None, "Returns a value.\n\n"
                       "The second paragraph explains ownership."),
                ("Raises", "`<bad-arg>` for zero."),
            ),
        )

    def test_does_not_treat_fenced_example_as_a_section(self):
        doc = (
            "Shows the spelling.\n\n"
            "```x2c\n"
            "Raises: this is example text\n"
            "```\n"
            "Raises: `<bad-arg>` for zero."
        )
        self.assertEqual(
            MODULE.doc_sections(doc),
            (
                (None, "Shows the spelling.\n\n"
                       "```x2c\nRaises: this is example text\n```"),
                ("Raises", "`<bad-arg>` for zero."),
            ),
        )

    def test_see_can_follow_raises_directly(self):
        doc = (
            "Returns a value.\n"
            "Raises: `<bad-arg>` for zero.\n"
            "See: Array.len, String.len"
        )
        self.assertEqual(
            MODULE.doc_sections(doc),
            (
                (None, "Returns a value."),
                ("Raises", "`<bad-arg>` for zero."),
                ("See", "Array.len, String.len"),
            ),
        )

    def test_api_key_does_not_need_a_blank_line(self):
        with self.assertRaisesRegex(MODULE.Fatal, "source-level API tier"):
            MODULE.parse_api_doc(
                "Array.len", 10,
                "Returns a value.\nAPI: advanced", "primary",
            )

    def test_render_raises_and_see_without_blank_lines(self):
        MODULE.SEE_INDEX.clear()
        MODULE.SEE_INDEX["Array.len"] = "array"
        item = MODULE.Item.__new__(MODULE.Item)
        item.name = "Array.get"
        item.line = 10
        item.doc = (
            "Returns a value.\n"
            "Raises: `<bad-arg>` for zero.\n"
            "See: Array.len"
        )
        module = MODULE.Module(
            "lib/array.x", "api", "", "arrays", "", (item,)
        )
        self.assertEqual(
            MODULE.render_doc(module, item),
            [
                "Returns a value.", "",
                "**Raises:** `<bad-arg>` for zero.", "",
                "**See:** [`Array.len`](#Array.len)", "",
            ],
        )

    def test_see_rejects_an_unknown_target(self):
        MODULE.SEE_INDEX.clear()
        item = MODULE.Item.__new__(MODULE.Item)
        item.name = "Array.get"
        item.line = 10
        item.doc = "Returns a value.\nSee: Array.missing"
        module = MODULE.Module(
            "lib/array.x", "api", "", "arrays", "", (item,)
        )
        with self.assertRaisesRegex(MODULE.Fatal, "not a documented"):
            MODULE.render_doc(module, item)

    def test_render_raises_preserves_source_wrapping(self):
        item = MODULE.Item.__new__(MODULE.Item)
        item.name = "Array.get"
        item.line = 10
        item.doc = (
            "Returns a value.\n"
            "Raises: `<bad-arg>` when the value is zero, or `<size-limit>`\n"
            "when it is too large."
        )
        module = MODULE.Module(
            "lib/array.x", "api", "", "arrays", "", (item,)
        )
        self.assertEqual(
            MODULE.render_doc(module, item),
            [
                "Returns a value.", "",
                "**Raises:** `<bad-arg>` when the value is zero, or "
                "`<size-limit>`\nwhen it is too large.", "",
            ],
        )

    def test_render_see_wraps_linked_targets(self):
        MODULE.SEE_INDEX.clear()
        for name in ("Array.len", "Array.capacity", "String.len"):
            MODULE.SEE_INDEX[name] = name.split(".", 1)[0].lower()
        item = MODULE.Item.__new__(MODULE.Item)
        item.name = "Array.get"
        item.line = 10
        item.doc = (
            "Returns a value.\n"
            "See: Array.len, Array.capacity, String.len"
        )
        module = MODULE.Module(
            "lib/array.x", "api", "", "arrays", "", (item,)
        )
        rendered = MODULE.render_doc(module, item)[2]
        self.assertGreater(len(rendered.splitlines()), 1)
        self.assertLessEqual(max(map(len, rendered.splitlines())), 79)


class FakeSymbols:
    def __init__(self, functions, rows):
        self._functions = functions
        self._rows = rows

    def functions(self, path):
        return self._functions[path]

    def rows(self, path):
        return self._rows[path]


class RejectingHashSymbols(FakeSymbols):
    def file_hash(self, path):
        raise AssertionError(f"content hash checked for {path}")


class FixedHashSymbols(FakeSymbols):
    def __init__(self, functions, rows, file_hash):
        super().__init__(functions, rows)
        self._file_hash = file_hash

    def file_hash(self, path):
        return self._file_hash


def func(returns="int", *params):
    return types.SimpleNamespace(returns=returns, params=params)


class PublicSurfaceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "src").mkdir()
        (self.root / "lib").mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, relative, source):
        path = self.root / relative
        path.write_text(source, encoding="ascii")
        return path

    def test_compiler_collection_filters_names_and_collects_types(self):
        path = self.write("src/widget.x", """/* widget.x -- widgets */
/** A widget value used by the compiler. */
typedef struct Widget { int value; } Widget;
#pragma private
/** Returns the widget value. */
int Widget.read(void) { return 1; }
int _widget_read(void) { return 1; }
int Widget__read(void) { return 1; }
""")
        symbols = FakeSymbols(
            {"src/widget.x": {"Widget_read": func()}},
            {"src/widget.x": {"Widget": object()}},
        )

        audit = MODULE.collect_public_path(
            path, symbols=symbols, root=self.root
        )

        self.assertEqual(audit.path, "src/widget.x")
        self.assertEqual(
            [item.name for item in audit.callables], ["Widget.read"]
        )
        self.assertEqual(
            [item.name for item in audit.declarations], ["Widget"]
        )

    def test_path_check_rejects_public_doc_on_excluded_callable(self):
        path = self.write("src/internal-callable.x", """/* internal -- test */
#pragma private
/** Returns an internal value. */
int _internal_value(void) { return 1; }
""")
        symbols = FakeSymbols(
            {"src/internal-callable.x": {}},
            {"src/internal-callable.x": {}},
        )

        with self.assertRaisesRegex(
            MODULE.Fatal,
            r"_internal_value carries a doc comment but is excluded",
        ):
            MODULE.collect_public_path(path, symbols=symbols, root=self.root)

    def test_path_check_rejects_public_doc_on_excluded_type(self):
        path = self.write("src/internal-type.x", """/* internal -- test */
/** An internal value. */
typedef int _InternalValue;
#pragma private
""")
        symbols = FakeSymbols(
            {"src/internal-type.x": {}},
            {"src/internal-type.x": {}},
        )

        with self.assertRaisesRegex(
            MODULE.Fatal,
            r"_InternalValue carries a doc comment but is excluded",
        ):
            MODULE.collect_public_path(path, symbols=symbols, root=self.root)

    def test_optional_library_collection_includes_callables_and_types(self):
        path = self.write("lib/extra.x", """/* extra.x -- extra values */
/** An optional extra value. */
typedef int Extra;
#pragma private
/** Returns an extra value. */
Extra extra(void) { return 1; }
""")
        manifest = {"lib/extra.x": ("optional", "Include it explicitly.")}
        symbols = FakeSymbols(
            {"lib/extra.x": {"extra": func("Extra")}},
            {"lib/extra.x": {"Extra": object()}},
        )

        audit = MODULE.collect_public_path(
            path, manifest=manifest, symbols=symbols, root=self.root
        )

        self.assertEqual(audit.path, "lib/extra.x")
        self.assertEqual([item.name for item in audit.callables], ["extra"])
        self.assertEqual(
            [item.kind for item in audit.declarations], ["alias"]
        )

    def test_path_check_ignores_content_hash_but_checks_artifact_rows(self):
        path = self.write("src/current-docs.x", """/* current -- test */
/** A compiler value. */
typedef int Current;
#pragma private
/** Returns the current value. */
Current current(void) { return 1; }
""")
        symbols = RejectingHashSymbols(
            {"src/current-docs.x": {"current": func("Current")}},
            {"src/current-docs.x": {"Current": object()}},
        )

        audit = MODULE.collect_public_path(
            path, symbols=symbols, root=self.root
        )

        self.assertEqual([item.name for item in audit.callables], ["current"])
        self.assertEqual(
            [item.name for item in audit.declarations], ["Current"]
        )

    def test_normal_collection_requires_current_content_hash(self):
        path = self.write("src/stale.x", """/* stale.x -- test */
#pragma private
/** Returns the current value. */
int current(void) { return 1; }
""")
        symbols = FixedHashSymbols(
            {"src/stale.x": {"current": func()}},
            {"src/stale.x": {}},
            "00000000",
        )

        with self.assertRaisesRegex(MODULE.Fatal, "symbol.*stale"):
            MODULE._collect_public_surface(
                path, "src/stale.x", symbols, compiler=True,
                check_hash=True, root=self.root
            )

    def test_path_check_requires_documentation(self):
        path = self.write("src/undocumented.x", """/* undocumented.x -- test */
#pragma private
int exposed(void) { return 1; }
""")
        symbols = FakeSymbols(
            {"src/undocumented.x": {"exposed": func()}},
            {"src/undocumented.x": {}},
        )

        with self.assertRaisesRegex(
            MODULE.Fatal,
            r"src/undocumented\.x compiler API exposed.*has no doc comment",
        ):
            MODULE.collect_public_path(path, symbols=symbols, root=self.root)

    def test_path_check_requires_type_documentation(self):
        path = self.write("src/undocumented-type.x", """/* type -- test */
typedef int Undocumented;
#pragma private
""")
        symbols = FakeSymbols(
            {"src/undocumented-type.x": {}},
            {"src/undocumented-type.x": {"Undocumented": object()}},
        )

        with self.assertRaisesRegex(
            MODULE.Fatal,
            r"src/undocumented-type\.x compiler API Undocumented.*"
            r"has no doc comment",
        ):
            MODULE.collect_public_path(path, symbols=symbols, root=self.root)

    def test_path_check_rejects_callable_artifact_mismatch(self):
        path = self.write("src/mismatch.x", """/* mismatch.x -- test */
#pragma private
/** Returns the supplied value. */
int exposed(int value) { return value; }
""")
        symbols = FakeSymbols(
            {"src/mismatch.x": {"exposed": func("int", "String")}},
            {"src/mismatch.x": {}},
        )

        with self.assertRaisesRegex(MODULE.Fatal, "symbol table says"):
            MODULE.collect_public_path(path, symbols=symbols, root=self.root)

    def test_path_check_rejects_declaration_missing_from_artifact(self):
        path = self.write("src/missing-type.x", """/* missing-type.x -- test */
/** A value missing from the artifact. */
typedef int Missing;
#pragma private
""")
        symbols = FakeSymbols(
            {"src/missing-type.x": {}},
            {"src/missing-type.x": {}},
        )

        with self.assertRaisesRegex(MODULE.Fatal, "Missing is absent"):
            MODULE.collect_public_path(path, symbols=symbols, root=self.root)

    def test_public_name_filter_matches_future_api_rule(self):
        self.assertTrue(MODULE._future_public_name("Compiler.parse"))
        self.assertFalse(MODULE._future_public_name("_parse"))
        self.assertFalse(MODULE._future_public_name("Compiler__parse"))

    def test_normal_collection_publishes_optional_callables_and_types(self):
        self.write("lib/optional.x", """/* optional.x -- optional values */
/** An optional value. */
typedef int Optional;
#pragma private
/** Returns an optional value. */
Optional optional_value(void) { return 1; }
""")
        manifest = {
            "lib/optional.x": ("optional", "Include it explicitly.")
        }
        symbols = FakeSymbols(
            {"lib/optional.x": {"optional_value": func("Optional")}},
            {"lib/optional.x": {"Optional": object()}},
        )
        with mock.patch.object(MODULE, "ROOT", self.root), \
                mock.patch.object(MODULE, "read_manifest",
                                  return_value=manifest), \
                mock.patch.object(MODULE, "read_tier_ledger",
                                  return_value={}), \
                mock.patch.object(MODULE, "load_symbols",
                                  return_value=symbols), \
                mock.patch.object(MODULE, "content_check") as content_check, \
                mock.patch.dict(MODULE.PRIMARY_EVIDENCE,
                                {"optional": "A focused test."}):
            modules = MODULE.collect()
        self.assertEqual(len(modules), 1)
        self.assertEqual(
            [item.name for item in modules[0].items], ["optional_value"]
        )
        self.assertEqual(
            [item.name for item in modules[0].declarations], ["Optional"]
        )
        content_check.assert_called_once_with(
            "lib/optional.x", symbols, root=self.root
        )

    def test_normal_compiler_collection_publishes_callables_and_types(self):
        self.write("src/widget.x", """/* widget.x -- widget compiler */
/** A compiler widget. */
typedef int Widget;
#pragma private
/** Returns a widget. */
Widget Widget.read(void) { return 1; }
int _widget_internal(void) { return 1; }
""")
        symbols = FakeSymbols(
            {"src/widget.x": {"Widget_read": func("Widget")}},
            {"src/widget.x": {"Widget": object()}},
        )
        with mock.patch.object(MODULE, "content_check") as content_check:
            modules = MODULE.collect_compiler(
                symbols=symbols, root=self.root
            )
        self.assertEqual([module.path for module in modules], ["src/widget.x"])
        self.assertEqual(
            [item.name for item in modules[0].items], ["Widget.read"]
        )
        self.assertEqual(
            [item.name for item in modules[0].declarations], ["Widget"]
        )
        content_check.assert_called_once_with(
            "src/widget.x", symbols, root=self.root
        )

    def test_normal_collection_fails_on_missing_public_documentation(self):
        self.write("src/undocumented.x", """/* undocumented.x -- compiler */
#pragma private
int exposed(void) { return 1; }
""")
        symbols = FakeSymbols(
            {"src/undocumented.x": {"exposed": func()}},
            {"src/undocumented.x": {}},
        )
        with mock.patch.object(MODULE, "content_check"):
            with self.assertRaisesRegex(
                MODULE.Fatal, r"compiler API exposed.*has no doc comment"
            ):
                MODULE.collect_compiler(symbols=symbols, root=self.root)

    def test_normal_collection_fails_on_missing_type_documentation(self):
        self.write("src/undocumented-type.x", """/* type.x -- compiler */
typedef int Undocumented;
#pragma private
""")
        symbols = FakeSymbols(
            {"src/undocumented-type.x": {}},
            {"src/undocumented-type.x": {"Undocumented": object()}},
        )
        with mock.patch.object(MODULE, "content_check"):
            with self.assertRaisesRegex(
                MODULE.Fatal,
                r"compiler API Undocumented.*has no doc comment",
            ):
                MODULE.collect_compiler(symbols=symbols, root=self.root)

    def test_type_sections_render_on_library_and_compiler_pages(self):
        declaration = types.SimpleNamespace(
            name="Widget", kind="alias", signature="typedef int Widget",
            line=2, doc="Stores one widget value."
        )
        library_type = MODULE.TypeItem("lib/widget.x", declaration)
        compiler_type = MODULE.TypeItem(
            "src/widget.x", declaration, compiler=True
        )
        library = MODULE.Module(
            "lib/widget.x", "optional", "", "widget values", "", (),
            (library_type,)
        )
        compiler = MODULE.Module(
            "src/widget.x", "compiler", "", "widget compiler", "", (),
            (compiler_type,)
        )

        library_page = MODULE.render_page(library)
        compiler_page = MODULE.render_compiler_page(compiler)

        for page in (library_page, compiler_page):
            self.assertIn("## Public types", page)
            self.assertIn("| [`Widget`](#Widget) | alias |", page)
            self.assertEqual(page.count('<a id="Widget"></a>'), 1)
            self.assertIn("`typedef int Widget`", page)
            self.assertIn("Stores one widget value.", page)

    def test_api_headings_omit_only_redundant_plain_anchors(self):
        bare_library = MODULE.Item(
            "car", "Var car(List value)", 2,
            "Returns the first value.", "advanced"
        )
        dotted_library = MODULE.Item(
            "Compiler.parse", "List Compiler.parse(Compiler compiler)", 3,
            "Parses one value.", "advanced"
        )
        library = MODULE.Module(
            "lib/widget.x", "optional", "", "widget values", "",
            (bare_library, dotted_library)
        )
        library_page = MODULE.render_page(library)
        self.assertIn("[`car`](#car)", library_page)
        self.assertIn("#### car", library_page)
        self.assertNotIn('<a id="car"></a>', library_page)
        self.assertEqual(
            library_page.count('<a id="Compiler.parse"></a>'), 1
        )

        bare_compiler = MODULE.Item(
            "bootstrap_build_request", "List bootstrap_build_request(void)",
            2, "Builds one request.", None, "compiler API"
        )
        compiler = MODULE.Module(
            "src/widget.x", "compiler", "", "widget compiler", "",
            (bare_compiler, dotted_library)
        )
        compiler_page = MODULE.render_compiler_page(compiler)
        self.assertIn(
            "[`bootstrap_build_request`](#bootstrap_build_request)",
            compiler_page,
        )
        self.assertIn("#### bootstrap_build_request", compiler_page)
        self.assertNotIn(
            '<a id="bootstrap_build_request"></a>', compiler_page
        )
        self.assertEqual(
            compiler_page.count('<a id="Compiler.parse"></a>'), 1
        )

    def test_compiler_pages_carry_the_provisional_label(self):
        module = MODULE.Module(
            "src/widget.x", "compiler", "", "widget compiler.", "", ()
        )
        compiler_index = MODULE.render_compiler_index((module,))
        compiler_page = MODULE.render_compiler_page(module)
        self.assertIn(
            "# Compiler API (provisional)",
            compiler_index,
        )
        self.assertIn(MODULE.COMPILER_BANNER, compiler_index)
        self.assertIn(MODULE.PROVISIONAL, compiler_page)
        self.assertIn("Widget compiler.", compiler_page)

    def test_library_index_carries_the_library_banner(self):
        module = MODULE.Module(
            "lib/widget.x", "api", "", "widget values", "", ()
        )
        self.assertIn(MODULE.BANNER, MODULE.render_index((module,)))

    def test_x2c_c_api_carries_the_mixed_source_banner(self):
        with mock.patch.object(
            MODULE, "definitions_for_path", return_value=()
        ):
            page = MODULE.render_x2c_api(())
        self.assertIn(MODULE.MIXED_BANNER, page)

    def test_summary_links_optional_and_compiler_pages(self):
        standard = MODULE.Module(
            "lib/array.x", "api", "", "arrays", "", ()
        )
        optional = MODULE.Module(
            "lib/typed-array.x", "optional", "", "typed arrays", "", ()
        )
        compiler = MODULE.Module(
            "src/compiler.x", "compiler", "", "compiler", "", ()
        )
        current = (
            "# Summary\n\n# Standard library\n\nold\n\n"
            "# Compiler and contributor internals\n\n- [Architecture](a.md)\n"
        )

        rendered = MODULE.render_summary(
            (standard, optional), (compiler,), current
        )

        self.assertIn("library/modules/typed-array.md", rendered)
        self.assertIn("# Libraries and Packages", rendered)
        self.assertIn("  - [Overview](library/overview.md)", rendered)
        self.assertIn("    - [lib/array.x](library/modules/array.md)", rendered)
        self.assertLess(rendered.index("- [Module Reference]"),
                        rendered.index("- [Advanced Topics]"))
        self.assertEqual(rendered.count("(guide/autodiff.md)"), 1)
        self.assertIn("# Compiler API (provisional)", rendered)
        self.assertIn("internals/compiler-api/compiler.md", rendered)
        self.assertLess(
            rendered.index("# Compiler API (provisional)"),
            rendered.index("# Compiler and contributor internals"),
        )
        self.assertEqual(
            MODULE.render_summary(
                (standard, optional), (compiler,), rendered
            ),
            rendered,
        )

    def test_build_generates_all_optional_and_compiler_pages(self):
        optional_stems = (
            "list-selectors", "match-recursive", "typed-array",
            "typed-list", "typed-map",
        )
        optional = tuple(
            MODULE.Module(
                f"lib/{stem}.x", "optional", "", f"{stem} values", "", ()
            )
            for stem in optional_stems
        )
        compiler = (
            MODULE.Module(
                "src/compiler.x", "compiler", "", "compiler", "", ()
            ),
        )
        summary = self.root / "SUMMARY.md"
        summary.write_text(
            "# Summary\n\n# Standard library\n\nold\n\n"
            "# Compiler and contributor internals\n",
            encoding="ascii",
        )
        with mock.patch.object(MODULE, "collect", return_value=optional), \
                mock.patch.object(MODULE, "collect_compiler",
                                  return_value=compiler), \
                mock.patch.object(MODULE, "render_x2c_api",
                                  return_value="c api\n"), \
                mock.patch.object(MODULE, "SUMMARY", summary):
            pages, rendered_summary = MODULE.build()

        for stem in optional_stems:
            self.assertIn(MODULE.PAGES / f"{stem}.md", pages)
        self.assertIn(MODULE.COMPILER_PAGES / "index.md", pages)
        self.assertIn(MODULE.COMPILER_PAGES / "compiler.md", pages)
        self.assertIn("library/modules/typed-map.md", rendered_summary)
        self.assertIn(
            "internals/compiler-api/compiler.md", rendered_summary
        )

    def test_internal_and_contract_source_docs_remain_errors(self):
        self.write("lib/unpublished.x", """/* unpublished.x -- private */
#pragma private
/** Returns an unpublished value. */
int unpublished_value(void) { return 1; }
""")
        for visibility in ("internal", "contract"):
            manifest = {
                "lib/unpublished.x": (visibility, "Not public.")
            }
            with self.subTest(visibility=visibility), \
                    mock.patch.object(MODULE, "ROOT", self.root), \
                    mock.patch.object(MODULE, "read_manifest",
                                      return_value=manifest), \
                    mock.patch.object(MODULE, "read_tier_ledger",
                                      return_value={}), \
                    mock.patch.object(MODULE, "load_symbols",
                                      return_value=FakeSymbols({}, {})):
                with self.assertRaisesRegex(
                    MODULE.Fatal, f"marked {visibility}"
                ):
                    MODULE.collect()

    def test_check_paths_reports_combined_coverage(self):
        one = MODULE.PathAudit(
            "src/one.x", (object(),), (object(), object())
        )
        two = MODULE.PathAudit("lib/two.x", (), (object(),))
        original = MODULE.collect_public_paths
        MODULE.collect_public_paths = lambda paths: (one, two)
        try:
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(MODULE.check_paths(["one", "two"]), 0)
        finally:
            MODULE.collect_public_paths = original
        self.assertIn("2 paths (1 callables, 3 types)", output.getvalue())


if __name__ == "__main__":
    unittest.main()
