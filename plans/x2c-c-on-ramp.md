# The C on-ramp

> Status: active - 4a implemented 2026-09-16 on a worker branch, awaiting
> integration. 4b (the landing page) has not started. termbox2 still does
> not translate as a unit; the next failures are listed under "End-to-end
> result" and are outside this plan.

## The result

A C programmer can rename a `.c` to `.x` and have it compile, and a C program
can call one x2c file, without hitting an avoidable failure or guessing a
compiler flag. Both directions appear on the landing page with worked
examples.

This splits into two deliveries. 4a changes the parser and needs no bootstrap
refresh; 4b is site and example work.

## 4a - The two parser gaps

### `_Generic`

Before 4a, `int g = _Generic((u.i), int: 1, default: 0);` failed with
`parse: expected atomic expression` at the `int` in the association list,
although `src/emit.x` already wrote `_Generic` into generated C.

The form follows the `sizeof` and `va_arg` sites in `src/expressions.x`:

- parse: `_parse_generic`, dispatched from `Compiler.parse_primary` beside
  `va_arg`;
- resolve: a `(generic CONTROL *ASSOCIATIONS)` case in `_resolve_content`;
- constant-expression classification: `_not_null_pointer_constant`
  classifies the selected value;
- emit: one case in `src/emit.x` printing the selection unchanged.

The AST is `(expr TYPE (generic CONTROL (association TYPE VALUE) ...
(association default VALUE)))`. Resolution resolves the control and every
value, then `_generic_selection` picks the association and the expression
takes the selected value's type. The C compiler makes the same choice from
the emitted text.

Selection applies C11's lvalue conversion to the controlling type: typedef
bases resolve through `Sym.normalize_declared_type` (which also maps system
names such as `size_t`), array and function types decay to pointers, and
leading qualifiers drop. Both sides normalize scalar spellings through
`Type.scalar`, so `unsigned int` equals `unsigned`. Types compare with
`List.equal`.

Recorded decisions:

- **Association type grammar.** Associations are parsed with
  `Compiler.parse_type_name` (qualifiers, specifier, pointers). A
  function-pointer or array type name must be spelled through a typedef.
  Rejected: `parse_simple_declaration`, whose declarator suffix reads the
  association's `:` as a bitfield width. Threading a no-bitfield flag
  through four declarator functions costs more than the case is worth; a
  decayed controlling type never matches an array association anyway.
- **No match.** Without a matching association the `default` value is
  selected. Without one, or when the controlling type is unknown (a `NULL`
  type, such as a call into an uncollected system function), the expression
  is left untyped and C alone decides. A compile-time `<macro-expr>`
  controlling type stays deferred. Rejected: an x2c diagnostic for a
  missing association, which would duplicate C's constraint error and would
  also fire where x2c's type knowledge is incomplete.
- **Selection is recomputed, not stored.** `_not_null_pointer_constant`
  calls `_generic_selection` again instead of reading a marker left in the
  AST, so constructed `(generic ...)` syntax needs no extra field.

Known limits, each reproduced with a `Var` boxing probe, where x2c selects
`default` while C selects another association: a character constant has
type `char` in x2c rather than C's `int`; qualifiers within one declarator
level compare in written order (`volatile const int *` against
`const volatile int *`); an enum type matches neither `int` nor `unsigned`.
The unselected associations are still resolved and transformed, as C still
type-checks them.

### `extern "C"`

Before 4a, a unit containing the C++ header guard failed with
`type: expected scalar type` at `extern "C" {`. Through `#include`, the same
header seemed to work, but only because the native compiler read it: shallow
collection skipped the braced group as a block, so x2c never saw the
declarations inside it. A method call on a type declared inside such a group
failed to translate.

Directives stay `(preproc ...)` nodes and both `#ifdef` branches are parsed,
so the `{` and `}` of the guard balance across two conditional regions.

- `Compiler.skip_linkage_brace` (in `src/parse.x`) consumes
  `extern <string> {` or a file-scope `}`. The token cursor's existing
  brace stack (`Compiler.next`) records the open group; a file-scope `}` is
  accepted only while that stack is non-empty, which at file scope can only
  be a linkage group because every other form consumes its own braces.
  `parse_top_level` and the shallow collection loop call it first, so units
  and collected headers behave alike. An unclosed group reports the existing
  `missing '}'` diagnostic and a stray `}` the existing `unexpected '}'`.
- `extern <string>` before a single declaration is read as `extern` in
  `_storage_class`.
- The group's braces are not emitted; generated C is C, and the surrounding
  `#ifdef __cplusplus` directives remain.
- Any string literal is accepted as the linkage name, and groups nest.
  Rejected: accepting only `"C"`, which would add a check that protects no
  generated output.
- `Compiler.script_statement_starts` treats a file-scope `}` as file scope
  so a script unit reaches the same path.

### Documentation

`docs/src/guide/from-c.md` gains "Bring existing C files": a `.c` renamed to
`.x` compiles; headers stay `.h` and are reached with `#include`; the guard
and `_Generic` examples. `docs/src/reference/language.md` gains a
"Generic selection" subsection under C foundation (it is expression syntax,
not preprocessing) and the file-naming rule and linkage groups in
"Host preprocessing".

### Fixtures

- `c-generic-selection` (`c stdout status`): file-scope initializer, macro
  expansion, return, argument, condition, method receiver, interpolation, and
  `Var` boxing that depends on x2c's selection for a `const` object, an
  array, a typedef, `size_t`, a function designator against a function
  pointer typedef, and pointee qualifiers.
- `c-linkage-guard` (`h c stdout status`): a unit carrying the guard with a
  plain `extern "C"` declaration, and an included `c-linkage-values.h`
  whose group declares a type and function used through method syntax.

No negative fixture: a malformed selection or unbalanced group already
reports an ordinary parse diagnostic at the offending token.

### End-to-end result

`termbox2.h` (the fetched integration source) with `#define TB_IMPL`
prepended, translated as a unit:

1. Before 4a: `type: expected scalar type` at `extern "C" {` (line 64).
2. After 4a: `parse: type () does not support indexing` at
   `tios.c_cc[VMIN] = 1;` (line 2148). `struct termios` comes from a system
   header whose field types x2c does not know, and indexing an untyped
   expression is rejected instead of delegated to C.
3. With that line rewritten in a scratch copy: `type: definition
   'tb_printf_inner' does not match prior prototype`, reported at the next
   function (line 2170). The prototype is `static` and the definition omits
   `static`, which C accepts.
4. With that rewritten too: the same indexing failure at
   `builtin_terms[i].caps[j]` (line 2629), a field of an anonymous struct
   array.

These are separate gaps and are not part of 4a.

## 4b - The landing page

Put both adoption directions above the fold with worked examples: a `.c`
renamed to `.x`, and a C `main` calling one x2c file through its generated
header.

Site code must be byte-identical to a runnable example: `examples/gallery.json`
maps slide markdown to a standalone example and
`tools/check-gallery-examples.py` rejects any difference. So each new sample
lands first as an example under `examples/`, with a row in
`examples/manifest.txt`, and the page references it.

Also fix `site/src/pages/index.astro:201`, which links a v0.12.0 Cosmopolitan
asset while the site ships 0.13.0.

## Validation

4a: `make verify`, then `tools/gate-state.py ensure agent-pr-check` at
integration. 4b: `make examples`, then the same gate.

## Plan review

- **Facts already established.** The parser already tokenizes and parses
  both branches of a conditional, and `Compiler.next` already maintains the
  brace stack, so the linkage change adds no branch or depth tracking. The
  resolver already types the controlling expression; selection reads that
  type and checks nothing else.
- **Reuse and deletion.** `_Generic` reuses `parse_type_name`,
  `Sym.normalize_declared_type`, `Type.scalar`, and `Emitter._semantic_type`.
  The one new public operation, `Compiler.skip_linkage_brace`, exists
  because two token loops (`parse_top_level` and the shallow loop) must
  agree. No new state is added to `Compiler`.
- **Why idiomatic.** Each change is a case in an existing dispatcher over an
  existing AST or token shape, written with `%(...)` patterns and templates.
- **Validators and fixtures.** No new validator or diagnostic. Two positive
  fixtures protect the added behavior; no negative fixture, because ordinary
  parse errors already describe malformed input.
