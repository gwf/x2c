# Hooks spike: what was refactored

> Status: reference
> Branch `gwf/hooks-spike` against `origin/dev` 7e946b86, 2026-10-08.
> `dev` and `main` are untouched.

## Result

Four features moved out of the compiler kernel into components:
`$auto`, `delegate`, `try`/`catch`/`finally` lowering, and catch selection
for static patterns. Conversion at the six documented destinations became
one kernel entry. The kernel gained one hook mechanism and an API for
components; its size is unchanged (656 lines added, 659 removed). Every
moved feature produces byte-identical generated C, except catch
selection, which changes C by design with identical program behavior.

## Features moved out of the kernel

### `$auto` (managed declarations)

- **Before.** `$auto(v)` produced a `managed-init` node. The kernel knew it
  in five places: the managed-declaration lowering in src/parse.x
  (`_managed_initializer`, `finish_managed_declaration`, two report macros,
  a bind arm), a Resolve arm in src/expressions.x, and a leftover check in
  src/transform.x.
- **After.** `$auto(v)` produces a generic `(claim auto MESSAGE VALUE)`.
  The kernel knows only claims: a declaration whose initializer is a claim
  is passed to the hook registered for its tag (`finish_claims`); an
  unconsumed claim reports its message. The `$auto` lowering is a 24-line
  component, `_auto_declaration` in src/builtins.x, registered by
  `hook <auto> builtin_auto_declaration;` in etc/builtin-macros.x.
- **Behavior.** Generated C and all eight `managed-init` diagnostics are
  byte-identical. Translation cost: +0.19 M instructions per use.

### `delegate` (method fallback through a field)

- **Before.** Method resolution had a hard-coded delegate search in
  src/expressions.x (`DelegateSearch`, `_resolve_delegate_method`,
  `_delegate_step`, `_delegate_receiver`, `_completion_delegates`), two
  diagnostics in src/expressions-reports.x, and `declare_delegate_field`
  in src/symbols.x.
- **After.** The parser keeps the `delegate` keyword and records a fact
  (`Sym.record_fact`). When method resolution finds nothing, the kernel
  calls the fallbacks registered by `hook <member> f;`. The search and its
  diagnostics are a 134-line component, `builtin_delegate_member` in
  src/builtins.x.
- **Behavior.** Generated C, diagnostics, and completion output are
  byte-identical. A resolution that finds its member pays nothing; a
  delegated call costs +0.13 M per use.

### `try`/`catch`/`finally` lowering

- **Before.** The cleanup walk in src/cleanup.x lowered `try` itself
  (`Walk._lower_try`, `_collect_try`, `_collect_catches`, the try rewrite
  cases, the try templates and slot functions, and the try case of
  `Preserve`).
- **After.** `hook <try> builtin_try_lowering;` registers a 244-line
  component in src/builtins.x. It returns data rows (`outer`, `exits`,
  `region`, `landing`) that the walk applies through its generic region
  operations. `defer` stays in the kernel as the cleanup service.
- **Behavior.** Generated C is byte-identical across src, lib, packages,
  and examples. Translation cost: +0.45 to +0.73 M per `try`.

### Catch selection for static patterns

- **Before.** Every catch arm prepared a runtime `MatchPlan` at its catch
  site, and the runtime matched plans at raise time.
- **After.** When every filtered arm of a clause uses a covered static
  pattern, the `try` component emits a `select` function that tests the
  arms in order; the catch site calls it at raise time in place of the
  plans (one optional field in lib/error.x). Other clauses keep the plans.
  45 of the 62 catch clauses in the compiler and runtime now use selectors,
  sharing 29 functions.
- **Behavior.** Same selection, at the same moment, with the same rules.
  Generated C changed in 18 fixtures; their stdout and status are
  identical, and the new output was reviewed and accepted. Raise and catch
  run 3 to 5 percent faster. Translation costs +32 M per `try` with
  distinct patterns and 8 M less when patterns repeat.

## Kernel entry made explicit

### Conversion at a position

- **Before.** Each lowering called `convert_expression` itself, and the
  interpolation rule lived in `convert_segment_to_string`.
- **After.** The six documented destinations (initializer, assignment,
  return, argument, interpolation hole, printf value) go through
  `Compiler.convert_at`. The interpolation and printf rules live there.
  Internal conversions that are not destinations keep their calls.
- **Behavior.** Byte-identical C. The kernel grew by 16 lines, because the
  call sites held little duplicated logic.

## What the kernel gained

- **Registration.** One `hook` declaration family, stored and exported
  like `keyword` aliases, usable from user files and from the compiler's
  own built-in source:
  `hook switch $m;` and `hook function $m;` (parse phase),
  `hook <switch> f;` and `hook <match> f;` (typed phase),
  `hook <TAG> f;` (claims), `hook <member> f;` (resolution fallback),
  `hook <try> f;` (cleanup walk).
- **Dispatch points.** Source `switch` and function definitions,
  `_step_tag` in the transform, claimed declarations, resolution misses,
  and the cleanup pre-pass. An unregistered hook costs nothing measurable.
- **Effects and queries.** Code-value effects for file initialization and
  node diagnostics; typing queries answered for project meta code through
  a nested request to the compiler.

## API added for components

In lib/meta.x, lib/meta-patterns.x, src/meta-sdk.x, and etc/meta-helper.x:
`x2c_code`, `x2c_fresh_name`, `x2c_effect_name`, `x2c_effect_support`,
`x2c_effect_initialize`, `x2c_diagnostic_fail_at` (with a category),
`x2c_fact_record`, `x2c_fact_lookup`, `x2c_member_resolve`,
`x2c_pattern_value`, `x2c_pattern_steps`, `x2c_pattern_nest`, and
`x2c_convert`. The typing queries already in lib/meta.x now also work from
project meta code.

## User-space prototypes (not in the compiler)

In plans/hooks-spike/: `string-switch.x` (parse-phase hook),
`typed-switch.x` (typed hook), `match-component.x` (static-pattern
`match`), `trace.x` (tracing every function), `member-alias.x` (a second
resolution fallback), `claim-noted.x` (a user claim), and `var-switch.x`
(conversion from meta code). Each is a single included file.

## Not refactored

- **Quotations.** A reader-prefix hook was tried on paper and rejected: it
  adds about 20 kernel lines and removes none (reader-prefix.md).
- **Protocols, class defaults, lambdas, operators.** Classified as
  separable in feature-modules.md, but not attempted.
- **The built-in `match`.** Unchanged; the component exists only in user
  space.

## Size against `origin/dev` (excluding generated files)

| Part | Added | Removed |
| --- | ---: | ---: |
| Kernel | 656 | 659 |
| Components (src/builtins.x, etc/builtin-macros.x) | 506 | 10 |
| API surface | 474 | 61 |
| Error runtime (lib/error.x) | 32 | 8 |

## Verification

`make verify` passes on the final tree: 942 unit tests, every compiler
fixture, and the focused probes. `doc-check` passes. The bootstrap is
converged (`stage-diff-0`).
