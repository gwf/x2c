# Calibration cases

These revisions show the patterns the lint rules are intended to surface.
They do not make a current finding removable; inspect current behavior before
editing. To check a revision, add a worktree for it and run the current
`builds/0/x2c lint` over that worktree's files; a unit whose old syntax the
current compiler no longer parses gets its token rules only.

## Static match capture extraction

Revision `e3a2b51a` is the required static-match calibration. Run:

```sh
git worktree add /tmp/x2c-e3a2b51a e3a2b51a
builds/0/x2c lint --rule static-match-capture /tmp/x2c-e3a2b51a/src/parse.x
```

The report must include `_install_declarator`, where a static `List.match`
result is immediately searched twice with `assoc` after manual List and tag
checks. Dynamic patterns, boolean-only method matches, and binding Lists that
leave the local branch are negative controls.

## Trusted compiler producers

Revision `2f9e05b9` is the required producer/consumer calibration. Run:

```sh
git worktree add /tmp/x2c-2f9e05b9 2f9e05b9
builds/0/x2c lint --rule silent-shape-guard /tmp/x2c-2f9e05b9/src/*.x
```

The report must include `SemanticEnvironment.declare_field_order`, whose
producers are `_parse_struct_or_union` and `_bind_syntax_declaration`. Those
parser paths pass complete aggregate field declarations, while the consumer
silently skips values that are not Lists,
declarations, binding lists, or binds. It must also report
`Emitter.emit_bind`, `_macro_collect_unit_bindings`, and
`Compiler.resolve_protocols`, which reads the `protocol_adoptions` map that
`_install_protocol_adoption` writes.

The same run must not report the following as consumers:

- `_macro_sdk_*` functions, because public SDK calls own the types and arity
  of their Lisp arguments; this does not authorize authenticating the origin
  of a canonical AST List returned by Lisp;
- `Ast.try_sequence`, which recognizes constructed syntax before binding;
- `Compiler.rebuild_protocols`, which decodes heterogeneous symbol rows;
- artifact readers in `src/collect.x`; or
- `_transform_cast`, `_transform_defer_stmt`, and `_transform_return`, which
  distinguish real pre- and post-lowered forms during fixed-point transforms.

These exclusions are explicit trust boundaries, not a general exemption for a
file, function prefix, recursion, or source `match`. In particular,
`_macro_collect_unit_bindings` contains source `match` and remains a required
positive case because it also silently skips an impossible candidate shape.

## Receiver-relative `Self`

Commit `bba961dc` initially added receiver-relative `Self`. Before commit
`414a15ed`, `src/parse.x` lost 109 lines and gained 18, while
`src/compiler.x` lost 23 and gained 15. The reduced version retained valid
`Self` lowering but removed the dedicated rejection paths for incompatible
receivers and use outside methods. Their diagnostic sidecars and two complete
negative fixture families disappeared.

Run:

```sh
builds/0/x2c lint --rule shape-diagnostics --rule recursive-validator \
  --rule validator-diagnostics OLD/src/*.x NEW/src/*.x
```

with `OLD` and `NEW` worktrees of the two revisions.

The old tree's findings must include `_finish_self_declaration` and the
recursive binding walk, and `git diff --name-status bba961dc 414a15ed --
unittest/compiler-fixtures` shows the `self-annotation-mismatch`,
`self-incompatible-receiver`, and `self-outside-method` fixture families
removed. The lesson is not that invalid `Self` must be accepted. It is that a new feature does not need a
second implementation whose only product effect is an earlier custom error.

## Private AST validator

Commit `52bb9891` removed 691 lines from `src/ast.x` and the compiler state,
hooks, diagnostics, and tests that existed to run its parallel AST schema.
The parser, transforms, and emitter already constructed and consumed the real
shapes.

Run:

```sh
builds/0/x2c lint --rule recursive-validator --rule shape-diagnostics \
  OLD/src/ast.x
```

with `OLD` a worktree of `52bb9891^`.

The parent's findings must include the removed `_ast_validate_*` family.
This case calibrates recursive validators and manual structural checks, not ordinary
local pattern selection.

The historical parent must also surface that family as connected machinery:

```sh
builds/0/x2c lint --rule validation-framework OLD/src/*.x
```

Ordinary recursive parser, transform, binder, and emitter functions are
negative controls. Recursion plus diagnostics does not make production work a
validation framework; a reported group must contain a validator-named helper.

## Non-returning failures

Commits `97c2a9e1` and `c4fee817` made the shared allocation, size, I/O, and
program Error causes non-returning, then removed null checks, fallback returns,
growth confirmations, cleanup branches, tests, and documentation that assumed
those operations could resume. The two commits removed 844 net hand-authored
source and test lines in `lib`, `src`, and `unittest`.

Run:

```sh
builds/0/x2c lint --rule return-after-raise --rule fallback-shared-cause \
  --rule fresh-literal-null-guard --rule growth-check OLD/src/*.x OLD/lib/*.x
```

with `OLD` a worktree of `97c2a9e1^`, and again at `c4fee817`.

The pair calibrates impossible result checks. It must not flag a
user-defined resumable cause or a documented absent result merely because
both are spelled with a return value.
