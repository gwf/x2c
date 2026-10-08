# Reader-prefix hook: negative result

> Status: reference
> Wave 4 entry W4-B of `execution.md`, on private branch `w4b-quotations`
> from `gwf/hooks-spike` `1f7618fe`, 2026-10-07. Stopped before editing
> source, under the entry's rule: the hook adds kernel code and removes none.

## Result

A reader-prefix hook cannot make quotations a module. Every
quotation-specific kernel line needs parser or binder state that no
registered target can reach. The registration would replace one condition in
`parse_primary` and add about 20 lines. No source changed.

## Proposed spelling and phase

`hook $! quotation;` in `etc/builtin-macros.x`, read by
`parse_keyword_definition` and stored in `kw_aliases` like the other hooks.
The phase is parse: `parse_primary` would consult the registration at `$`
followed by `!`. Parse is required, because the body's `$name` holes resolve
against the locals visible where the quotation is written.

## What a registered target would have to do

A registered target receives the prefixed form. Nothing remains for it to
do after reading, because reading the body is the quotation's work. The
quotation-specific code, in non-blank lines of `src/macros.x`:

| Code | Lines | State it needs |
| --- | ---: | --- |
| `parse_macro_quotation`, `_quotation_kind`, `_typed_quotation` (1564-1623) | 55 | token cursor, `macro_holes`, scope push |
| `_expression_holes`, `_hole_local`, `_expression_hole` (1624-1680) | 55 | token scan, `bind_syntax` of hidden locals |
| `_quoted_type`, `_checked_type`, `_quoted_type_name` (1681-1721) | 38 | type parser, literal cache |
| `_quotation`, `_quoted_cons`, `construction`, `_built_*` (1722-1845) | 117 | `Definition` reader, literal cache, `convert_expression` |
| typed construction, `written_keys`, `_typed_cells`, `_typed_hole` (1846-1945) | 92 | literal cache, `resolve_expression` |
| `_quoted_role`, `_quoted_hole`, `_quoted_holes` (1946-1984) | 35 | `sym.lookup`, `binding_is_local`, cursor |
| quoted syntax: `land_quotation`, `Landing` (3982-4104) | 116 | `bind_syntax`, `_private_name`, `macro_stack`, `SymTxn` |
| two diagnostics (177-190), `.quotation` uses in `Definition` | 18 | cursor |

The total is about 526 lines, comments included.

Targets that a hook can name today:

- A macro receives arguments that the parser has already read in the
  caller's context. Outside a template, `$name` is a macro invocation there,
  not a hole, so the body would have to be read in quotation mode before
  the macro runs. That reader is the code above.
- A meta function, whether project, library, or linked through
  `src/builtins.x`, receives and returns Lists. `lib/meta.x` and
  `src/meta-sdk.x` provide no parser, token, symbol-table, or literal-cache
  access.
- A kernel parse function is a valid target. However, a table that maps the
  registered name to it is a closed vocabulary with one row. It changes
  nothing that `parse_primary` does today.

## Count for the narrowest design

The design is the kernel-function registration above, sketched without
compiling:

- Added, about 20 lines: a `hook $!` branch in
  `keyword_form_is_definition` and `parse_keyword_definition`, a 12-line
  `_prefix_hook_definition` with its compile-time effect, and a lookup in
  `parse_primary`.
- Removed, 0 lines. The `c.peek(1) == <!>` test stays, because `$` alone
  starts a macro invocation. The nested-quotation skip in
  `_expression_holes` still recognizes `$!` lexically.

## Alternatives checked

- **Quotation as a macro with a quotation-body hole kind.** The new hole
  kind would read its argument with `parse_macro_quotation`'s code. The
  extra macro layer adds an expansion, origin anchors, and a transaction to
  every quotation. Therefore generated C would change for the
  about 230 quotations in `src/` and `lib/`.
- **Tokenizer rewrite of `$!Kind{` into `macro Kind() =>`.** Anonymous
  macros declare explicit parameters. Inferring parameters from visible
  locals is `_quoted_hole`, so that code moves and is not deleted. Typed,
  `Type`, and `Param` quotations bind nothing and build where they are
  written. No anonymous macro form matches them.
- **Moving construction or landing into linked meta code.** Both call
  compiler internals listed above. Landing also runs each time the compiler
  binds code that its own quotations built.

## Observation outside this entry

`_quotation` repeats the reading sequence of `parse_macro_definition`:
`naming`, `nested`, the `enclosing` link, `locals`, `using`, `announce`,
`body`, and `finish`. A shared `Definition` reader method would remove about
six lines. It is an ordinary simplification, not a hook.
