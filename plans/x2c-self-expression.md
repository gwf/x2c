# x2c Self-Expression

> Status: active, 2026-10-01. Phase 0 (five reproduced defects) is on
> `dev` at ff9946c8; the `x2c_func_shared` emission change needed the usual
> second bootstrap round. L1-L4 are decided (5-10 below). L1, L3, the
> `({1})` fix, and template destructuring hygiene landed together; L2 and
> forward-name hygiene (decision 11) are in progress; L4 is next. Five further defects found while scoping L1-L4 are
> listed below. Waves 1-3 are decided and not started. L1-L4 are scoped;
> Gary's decisions are pending.

## Result

The compiler, runtime, commands, and packages state each relationship at
the largest ordinary x2c form that can own it. A naming or grammar rule is
written once and projected; a grammar fact has one recognizer; a
specialization calls its general operation; a family macro states its
structure and lets ordinary conversion supply the rest; a generated helper
is one complete template that enters the normal binder. Real
representation and phase differences stay explicit.

Behavior and public names stay the same, except where a Phase 0 fix
restores documented behavior or a decision below says otherwise.

## Source

A read-only review of `dev` at `b7bdb5b2` (2026-10-01) merged two
independent surveys. Every item below was checked against current source;
the defects were reproduced with `builds/0/x2c`. Line counts are estimates
from line ranges, not measured patches. Item ids (H, P, L) match the
review page.

## Decisions

Recorded 2026-10-01 from Gary:

1. `offsetof` is fixed, not deleted: x2c source accepts
   `offsetof(type, member)`.
2. `Func.apply_value(fn, v)` and `Func.apply_values(fn, a, b)` are added as
   public inline operations (H10, Wave 2).
3. `x2c-lint` checks against the non-returning cause list it was built with
   (`$error.nonreturning.causes()`), not the checkout being linted.
4. `$map.core.family` keeps its callback parameters. H8 generates the
   per-family scaffold instead of removing parameters.

Recorded 2026-10-01 from Gary, after the L1-L4 scoping:

5. L1: `x2c.syntax.type` resolves syntax a template left untyped at the
   expansion point; the book says so.
6. L2: the parts of `%()`, `%[]`, `%{}`, `%""`, and bare `[...]` and `{...}`
   literals evaluate once each, left to right; function-call arguments keep
   C's unspecified order.
7. L3: collection tries every file-scope Unit macro defined in the unit;
   imported and protocol-row macros stay mandatory, and a failed local
   expansion keeps nothing.
8. L4: `({ ... })` is accepted in ordinary source when the braces contain a
   top-level `;`, so `({})` and `({a: 1})` keep their current meaning.
9. L4: a `defer` or managed declaration directly inside a statement
   expression is an error.
10. Fix `({1})` and the two template hygiene defects.
11. Forward names in templates (Gary, 2026-10-01): a name that nothing
    declares where a closed macro was defined binds a declaration the same
    expansion introduces, including one a nested macro makes from a literal
    `Name` in this body. A later global keeps working as today. A caller's
    local never captures it; with no such declaration, x2c reports the name
    instead of emitting C.

Order: L1 and L3 with the three defects first, then L2, then L4.

## Phase 0: reproduced defects

One batch, one gate. Each fix adds regression coverage in the suite that
owns the behavior.

| Defect | Cause | Fix |
| --- | --- | --- |
| `~(unsigned) n` does not parse | `_parse_unary_op` (src/expressions.x:447) gives `~` a unary-expression operand | `~` joins the cast-operand group (C 6.5.3) |
| `offsetof(struct P, b)` does not parse | lib/scan.x never produces `<offsetof>`; the parse, resolve, and type rows are unreachable; the emitter has no case | Recognize by spelling beside `va_arg`; add the emitter case |
| `case %((!not ?x foo))` rejected | `MatchCaptureLayout.analyze` (lib/match.x:231) computes slots from the raw pattern after normalizing it (H4) | Compute slots from the normalized pattern |
| `Lisp.bind` with a direct function crashes on the second session | `Lisp.bind` moves the shared file-static `Func` into the session, which frees it | Static `Func` handles are never moved or freed |
| `x2c-lint` drops two rules outside the repo root | commands/lint/validation.x:41 reads `lib/error-macros.xmacro` from the working directory | Use `$error.nonreturning.causes()` (decision 3) |

The `Lisp.bind` fix marks the compiler's direct-conversion handle through
an internal `x2c_func_shared` constructor; `Func.move` owns the rule and is
classified internal, not public. `MatchLower._compile_set` keeps its own
copy of the `!set` capture test because `_set_capture` is private to
lib/match.x.

Not in Phase 0: the statement-cast warning gap (src/expressions.x:276) is
fixed by P7, and template splice order (L2) waits on its design decision.

### Defects found while scoping L1-L4

Each is accepted by x2c and emits C that the C compiler rejects.
Reproduced with `builds/0/x2c` on 2026-10-01; not yet fixed.

| Defect | Cause |
| --- | --- |
| `$let(local, 7)` on a template local emits `macro` as a C type | `x2c_syntax_type` (src/meta-sdk.x:58) returns the `(<macro-expr>)` placeholder (L1) |
| A Lisp-built `(expr () (parens (block ...)))` is never bound; `String s = $wrap(3);` emits an int initializer | `_resolve_parens` (src/expressions.x:2966) treats the block as an expression (L4) |
| `int z = ({1});` emits `({ 1 })` without a semicolon | The parenthesized composite path |
| Two-name `foreach (Var (key, val), ...)` in a template: the body keeps `val` after the declaration is renamed | Template hygiene for literal names |
| A template passing literal `k` and `k * 2` to an inner macro: the loop variable is renamed, the expression is not | Template hygiene for literal names |

Status of these: `$let` is fixed by L1; `({1})` and the destructuring
`foreach` are fixed in the L1/L3 batch. The forward-name case (`$repeat(k,
3, k * 2, total)`) is held: the worker's fix let an undeclared free name
in a closed template bind a local at the expansion site (a probe printed
the caller's `x`), which contradicts "free identifiers written literally
in a body resolve where the macro was defined". It needs Gary's choice
between that rule, a narrower rule that binds only declarations the same
expansion introduces, and a diagnostic.

Also found, not yet fixed: a brace with no destination type, such as a
variadic argument (`printf("%d\n", {10})`), emits invalid C; and with
`int k = 0; $outer(k);` the nested macro's public loop variable `k`
captures the caller's `k` (prints 0), through the stale-local branch of
`_shadow_identifier`.

## Wave 1: direct substitutions

Equivalence is obvious or by construction. Focused fixtures per item.

- H1 One template instantiation walk: lib/match.x `_capture_replace` and
  `_replace` differ only in the binder lookup; one Unit macro writes both.
- H6 `_targets` (src/meta-group.x:644) builds `map-entry` rows and lets
  `$map_value` and ordinary Map lowering construct the table; keep the
  `Func` conversion and its `malformed` catch. Compare generated output.
- H7 Delete the 34 unreferenced `builtin_targets` rows (src/builtins.x:970)
  and the five Lisp forwarders in etc/compiler-sdk.xlisp that shadow
  native SDK bindings; move the three `_x2c.embed.text` callers.
- H9 Delegate: `Iter.zip` to `zip_with(NULL)`; `Map.setindex` to `set`;
  drop `Iter.accumulate`'s checks that `init` and `try_next` make;
  `Var.fallback_str`/`repr` through the Buffer writers; List and Array
  fold, any, all, find through Iter. Typed-array integer update calls
  `$integer.raw` (keep its shift check; needs `_integer_raw` visible from
  the header).
- H12 One guarded-initializer macro: delete `$cache_function` and
  `$header_cache_setup` (src/cache.x) in favor of the generate.x shapes.
- H14 Commands call existing owners: `Path.make_dirs`, `Map.getdefault`,
  `Compiler.match_pattern_binders`, `in` for lint's `_among`.
- H17 One table per closed vocabulary: target kinds (cli.x and project.x
  plus four projections), help groups, library load order (macros.x),
  match-site entries (emit.x:811).
- H18 Named patterns in src/grammar.xmacro: `source_any_lambda`,
  `source_declarator_row`; `source_pattern` delegates to
  `source_pattern_with`; `Type.is_reference` replaces 13 copies of
  `car() == <&> || car() == <opt-ref>`.
- H19 `lisp_binder_lets` (lib/lisp-init.x:162) returns a `%()` template.

## Wave 2: needs tests or measurement

- H2 `Ast.designated` becomes the one same-object walk; `lvalue_binding`,
  `_defer_direct_binding`, `_expression_is_addressable`, and
  `ast_direct_identifier` classify its end node. Add `Ast.written_operand`
  for the three write-operand copies. The defer path gains the array-field
  step on purpose; check `f().arr[0]`.
- H3 One `Symbol.binary_precedence` for parser, emitter (+3), and macro
  lookahead; SymbolSets for increments, prefix operators, and primary
  starts. Probe `%`-token spelling inside `%<<>>`.
- H5 Generate etc/lisp-values.xlisp bind rows with a `natives` defmacro over
  the curated name list (15 explicit exceptions) and the selectors with one
  folding macro. Run the warm-load timing tests.
- H8 `$map.scaffold` generates slot accessors and invariant raisers for the
  five Map families; `$array.typed.observe` writes buffer calls inline;
  `$scalar` boxes through immediate boxers; `$native.update` uses ordinary
  conversion. `$scalar` and varops are hot: take a performance checkpoint.
- H10 Add `Func.apply_value`/`apply_values` (decision 2) and replace the
  twelve `FuncArg` stanzas. Preserve char boxing and noninvocation on
  empty input.
- H11 One `_settle_reference` narrowing helper for parsed and bound `if`.
- H13 Diagnostic entries and locations read by one pattern each
  (diagnostics.x, editor.x, `_thaw_origin`).

## Wave 3: packages

Package builds fetch sources and sit outside `make check`; run each
package's own tests.

- H15 `$uv.phase` (idle, prepare, check) and a stream family (tcp, pipe) in
  libuv; `$torch.handle` for five torch handles; a `$cleanup.by` macro for
  the one-line Cleanup forwards; `$curl.setopt` stringifying the option
  name; delete the unreachable `catch %(?snapcause *)` arms around
  `Error.snapshot` in libcurl, libuv, and torch. Probe that unit-macro
  public methods reach the package interface (see L3).
- H16 One `$json.reader` template for yyjson's immutable and mutable trees,
  projecting API names through a meta `x2c_ident` helper.

## Prototypes

Each is a short spike that must show its measurement or a smaller diff
before adoption.

- P2 first: `_proto_cached` callers build a capturing closure
  (`Func_new_context`) on every protocol member lookup, including cache
  hits. A `$memo` decorator removes the allocation; measure translation.
- P1 `$ast.walk` for eight worklist walks (natural form needs L1).
- P3 `_step` as one match (measure switch versus match); `_from_ast` only
  with compatible patterns, since its selectors tolerate loose rows.
- P4 operator lowering passes captured types; one `_change` for prefix and
  postfix.
- P5 protocol-update and forwarding helpers as complete `macro open Unit`
  functions; prove volatile access counts and helper identity.
- P6 REPL `_lower_scan` as one match. P7 one type-name operand and cast
  constructor (also fixes the statement-cast warning). P8 liveness
  decorator deriving the operation from the method name. P9 one graph
  peel helper. P10 indirect contexts through `capture_environment`. P11
  `$class_string_body` owns its Buffer operations. P12 command arguments
  through `Args.parse` tables. P13 `Frontend.open_reporting`.
- P14 smaller consolidations: one integer-literal decoder; initializer
  conditions as Expression templates; one macro projection binder owner;
  the third copy of lib/meta.x builders in etc/meta-helper.x; the Lisp
  callback bridge through a rest `Func`; SymTxn slot ledger; manifest
  field ledger.

## Language design

Scoped 2026-10-01; Gary's decisions go here before any work starts.

- L1 `foreach` inside macro bodies fails with "type (macro-expr) is not
  iterable". Cause: `x2c_syntax_type` returns the template placeholder
  type to compile-time code that runs before binding. Recommended: resolve
  a `(<macro-expr>)` type at the expansion site in that one function (two
  lines); a scratch build passed `make verify` and stage-1 self-translation
  was byte-identical. Also fixes `$let` on template locals. Deletes almost
  nothing; it is a correctness fix.
- L2 `%()`, `%[]`, `%{}`, `%""`, and bare collection literals evaluate their
  parts in C argument order. x86-64 gcc, a documented host compiler,
  evaluates right to left, so user programs and the compiler's own cache
  numbering (src/callables.x:1182) differ from clang builds. Recommended:
  sequence parts left to right in transform when two or more are not
  stable, through temporaries in a statement expression (about 50-60
  lines, free at -O2), then fold about 18 emitter helpers (about -75).
  Needs a local bootstrap refresh between capability and adoption.
- L3 Collection skips Unit macros defined in the same file unless they
  contain protocol rows; imported `.xmacro` Unit macros always expand.
  Recommended: try the remaining local Unit macros under a diagnostics hold
  and keep nothing on failure (about 15 lines), which honors the book's
  existing "if expansion succeeds" wording. Deletes the four hand prototype
  blocks (45 lines) after a local bootstrap refresh.
- L4 No source form for `({ ... })`; seven producers build the canonical
  `(parens (block ...))` by hand. Recommended: accept it in source when the
  braces contain a top-level `;`, so `({})` and `({a: 1})` stay literals;
  bind the block in `_resolve_parens` (also fixes the Lisp-built defect);
  reject a top-level `defer` or managed declaration inside one. About 45
  lines; deletes about 20, or about 45 with a measured callables rewrite.

Backlog signals, not scheduled: L5 grammar macros as static constructors;
L6 string-to-atom in compile-time Lisp; L7 Lisp callables crossing a
native `Func` parameter; L8 a protocol adoption naming its method; L11
pointer-handle Var converters from the adoption; L12 an `ErrorSlot` owner
for package callback errors; L13 `TagId` generated from the ledger; L14
`_Alignof(type-name)` with a Type hole.

## Not doing

Checked and rejected during review: positional Type and datum decoding to
exact patterns (loose-arity contracts); `_unwrap_origin` through
`without_origin`; removing joint zip guards or Map value validation;
deriving Map keys from enumerate; plain `Frontend.open` in the commands;
consolidating native wrappers whose lifecycles differ; freeze and thaw as
one codec; generated families such as torch-ops.x.

## Validation and delivery

Workers build and run their own fixtures; the orchestrator integrates each
wave as one batch and runs `tools/land-dev` once per batch. Waves 2 and 3
items marked hot take a performance checkpoint under
agents/performance-checkpoints.md before publication. No new gate or
recurring check is added.

## Plan review

- Trusted facts: each consolidation keeps the producing operation as the
  owner (`_normalize_pattern`, `Ast.designated`, `$integer.raw`,
  `Iter.zip_with`, Map lowering, `$error.nonreturning.causes()`), and no
  consumer rechecks what the owner established. H9 removes checks that
  `Iter.init` and `try_next` already make.
- Deleted or reused: parallel walks, tables, and helper copies listed per
  item. New lasting mechanisms are `$match.instantiate`, `Ast.designated`
  (moved), `Ast.written_operand`, `Symbol.binary_precedence`,
  `$map.scaffold`, `Func.apply_value`/`apply_values`, `Type.is_reference`,
  and the package family macros; each replaces two or more copies.
- Idiomatic x2c: every replacement is a match pattern, a `%()` template, a
  Unit or Statement macro, a compile-time Lisp macro, or a delegation;
  none adds a runtime framework, registry, or configuration record.
- Validators and diagnostics: none added. Phase 0 restores documented
  behavior; its regression tests protect the four reproduced wrong
  outputs or crashes and the lint rule loss.
