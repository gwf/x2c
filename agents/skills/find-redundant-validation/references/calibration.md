# Calibration cases

Apply PR-2, PR-3, PR-4, PR-10, FA-7, and TE-2 in
[the standard](../../../x2c-code-standard.md) to this evidence.

These cases show the patterns the lint rules are intended to surface.
They do not make a current finding removable; inspect current behavior before
editing. The cases predate the repository's history, which begins at
`4235c3837` (2026-09-05), so their revisions cannot be checked out. Use them
to judge whether a rule recognizes the intended pattern.

## Static match capture extraction

`static-match-capture` must report `_install_declarator` in the former
`src/parse/parse.x`, where a static `List.match` result is immediately
searched twice with `assoc` after manual List and tag checks. Dynamic patterns, boolean-only method matches, and binding Lists that
leave the local branch are negative controls.

## Trusted compiler producers

`silent-shape-guard` must report `SemanticEnvironment.declare_field_order`,
whose producers are `_parse_struct_or_union` and `_bind_syntax_declaration`.
Those parser paths pass complete aggregate field declarations, while the
consumer silently skips values that are not Lists, declarations, binding
lists, or binds. It must also report
`Emitter.emit_bind`, `_macro_collect_unit_bindings`, and
`Compiler.resolve_protocols`, which reads the `protocol_adoptions` map that
`_install_protocol_adoption` writes.

The rule must not report the following as consumers:

- `_macro_sdk_*` functions, because public SDK calls own the types and arity
  of their Lisp arguments; this does not authorize authenticating the origin
  of a canonical AST List returned by Lisp;
- `Ast.try_sequence`, which recognizes constructed syntax before binding;
- `Compiler.rebuild_protocols`, which decodes heterogeneous symbol rows;
- artifact readers in `src/collect/collect.x`; or
- `_transform_cast`, `_transform_defer_stmt`, and `_transform_return`, which
  distinguish real pre- and post-lowered forms during fixed-point transforms.

These exclusions are explicit trust boundaries, not a general exemption for a
file, function prefix, recursion, or source `match`. In particular,
`_macro_collect_unit_bindings` contains source `match` and remains a required
positive case because it also silently skips an impossible candidate shape.

## Receiver-relative `Self`

The first implementation of receiver-relative `Self` was later reduced:
`src/parse/parse.x` lost 109 lines and gained 18, while
`src/compiler/compiler.x` lost 23 and gained 15. The reduced version retained
valid `Self` lowering but removed the dedicated rejection paths for
incompatible receivers and use outside methods. Their diagnostic sidecars and
the `self-annotation-mismatch`, `self-incompatible-receiver`, and
`self-outside-method` negative fixture families disappeared.

`shape-diagnostics`, `recursive-validator`, and `validator-diagnostics` must
report the first version's `_finish_self_declaration` and its recursive
binding walk. The lesson is not that invalid `Self` must be accepted. It is
that a new feature does not need a second implementation whose only product
effect is an earlier custom error.

## Private AST validator

One change removed 691 lines from `src/ast.x` and the compiler state,
hooks, diagnostics, and tests that existed to run its parallel AST schema.
The parser, transforms, and emitter already constructed and consumed the real
shapes.

`recursive-validator` and `shape-diagnostics` must report the removed
`_ast_validate_*` family. This case calibrates recursive validators and
manual structural checks, not ordinary local pattern selection.

`validation-framework` must also report that family as connected machinery.
Ordinary recursive parser, transform, binder, and emitter functions are
negative controls. Recursion plus diagnostics does not make production work a
validation framework; a reported group must contain a validator-named helper.

## Non-returning failures

Two changes made the shared allocation, size, I/O, and program Error causes
non-returning, then removed null checks, fallback returns, growth
confirmations, cleanup branches, tests, and documentation that assumed those
operations could resume. They removed 844 net hand-authored source and test
lines in `lib`, `src`, and `unittest`.

`return-after-raise`, `fallback-shared-cause`, `fresh-literal-null-guard`,
and `growth-check` must report the checks those changes removed. The pair
calibrates impossible result checks. It must not flag a user-defined
resumable cause or a documented absent result merely because both are spelled
with a return value.
