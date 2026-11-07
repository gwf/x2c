# Public release readiness

> Status: implementation authorized, 2026-11-06; work in progress.
> Baseline: `68ebfece63702c3e1ecc249bd8bbd85e5997ad8f` from `origin/dev`.
> Four bounded compiler repairs and packaging work are specified below.
> Version 0.16.0 is selected. Measure the minimal Regex repair before acceptance.

## Result and scope

Make supported source compile correctly through existing compiler operations,
complete a few existing contracts, and prepare self-contained release archives.
A reproduced defect is not automatically a release blocker. Repair cost,
normal workloads, and x2c's freedom at native boundaries determine priority.

Website implementation, content, browser testing, site builds, and deployment
belong to Gary's separate session. This plan includes the language book and
release/archive producers, but no edits under `site/`. Final release assembly
is a coordination boundary; this session does not take ownership of its site
portion. Both sessions began at the baseline above.

No new runtime ABI, caller obligation, syntax, cache, representation, generic
validator, recurring gate, or benchmark campaign is proposed. Preserve the
current architecture. If a bounded repair grows into one of those changes,
stop that item and present the concrete alternative and cost.

## Evidence already established

The baseline was built with `make build-safe`. Focused probes reproduced all
four compiler issues below, Regex stack failures, and missing source-package
license files. The workspace review retains inputs and logs in `.context/`
and `/tmp`; the essential reproductions are also described here.

The local macOS baseline passed 1,217 unit tests, 140 book output examples,
65 curated examples, shipped-command smoke tests, and the scratch installed
package/command probe. This does not establish final candidate readiness or
Linux behavior. No source repair has been made.

## Order of work

1. Implement the four compiler repairs as one coherent, reviewable batch.
   They can remain separate commits; do not broaden a repair to adjacent
   speculative defects. Use focused checks while developing.
2. Complete the package/license contents as an independent change.
3. Follow Gary's Regex choice below. Do not delay the independent work while
   evaluating that choice.
4. Prepare the selected release version near candidate selection, after the
   included changes are known.
5. Submit ready work for shared integration by default. The integration owner
   combines the source work with the separate website work, refreshes generated
   artifacts, and runs existing publication validation on the combined tree.
6. Obtain final candidate/platform evidence before Gary's publication decision.

Implementation is authorized; staging, tags, advancing main, and production
promotion are not. Material code or performance costs return to Gary.

## 1. Calls through pointers to function typedefs

**Result.** These two equivalent callable spellings must box arguments and
produce the same result:

```x2c
typedef String NamerFunction(Var value);
typedef String (*NamerPointer)(Var value);
```

With `name_of(Var value) => value.repr()`, calling a `NamerFunction *` with
`42` currently emits an unboxed integer and fails native compilation. The
`NamerPointer` control builds and prints `42`.

**Change.** Reuse `Sym.normalize_declared_type` from `src/symtab/types.x`.
It already resolves typedef bases beneath declarator modifiers.

- In `src/expressions/calls.x`, `_finish`, retain `callee_type.apply()` as
  the fast path. Change only the unsuccessful fallback from
  `resolve_key(...).apply()` to `normalize_declared_type(...).apply()`.
- In `src/transform/expressions.x`, `_call`, retain both direct-signature
  match arms. Change only its fallback lookup to `normalize_declared_type`,
  then reuse `Type.function_parts` and `_typed_call`.

Both sites are necessary: result typing does not rewrite the callee's stored
source spelling. Do not introduce a resolver or normalize every call eagerly.
Do not broaden `_check_arity`, Iter completion, or rest-call reconstruction
without a separate reproduced problem selected for repair.

**Verification.** Extend `call-pointer-arguments` with the function-typedef
pointer form, integer boxing, and an expression that uses its String result.
Keep the existing pointer-typedef control. Require successful translation,
native compilation, and the expected output through the existing fixture.

**Cost.** Two existing fallback lookups change. Direct-call fast paths and
emitted function calling conventions remain unchanged. No runtime checks.

## 2. Constructed array dimensions

**Result.** This ordinary composition must emit an array of three elements:

```x2c
macro Expr $width() => 3;
macro Unit $make(Name $name) { int $name[$width()]; }
$make(values);
```

It currently fails interface emission. Passing `$width()` as an explicit Expr
argument succeeds. The issue also remains in `unittest/STATUS.md`.

**Change.** In `src/parse/declarators.x`, extend `_finish_fnmod` with a
structural `(dim ?expression)` arm. Bind that expression with the existing
`c.bind_syntax(expression, <expression>, NULL)` and retain it in the modifier.
Preserve empty `(dim)` and current prototype handling. The existing modifier
walk serves constructed declarations and parameters; add no AST traversal,
emitter repair, or constructed-syntax origin check. Rename the local helper
pair only if needed to describe their expanded responsibility.

**Verification.** Extend `macro-construction-regressions` with file-scope and
block declarations, plus a constructed parameter dimension. Check the array
size and successful interface emission. Retain `macro-argument-kinds` as a
binding control. A small compile-time counter probe must show that a retained
expansion is not evaluated twice; reuse normal binding ownership rather than
adding bookkeeping if the probe exposes a problem.

**Cost.** One structural case in the existing modifier walk. Ordinary source
already binds its dimension in `_array_suffix`; do not add another pass there.

## 3. Callback result qualifiers

**Result.** A source returning `const char *` must not become a callback
returning `char *` through `$x2c.callback.adapt`. The current generated thunk
warns in C and permits a later write through the pointer. The book already
requires an exact non-void result type; this is not a new native-C policy.

**Change.** Keep responsibility in `src/callables/callbacks.x`:

- In `_check_signature`, compare the normalized declared results from
  `cb.result` and `cb.source.apply()` using `Sym.normalize_declared_type`.
  Do not compare results after `canonicalize` has erased qualifiers.
- Remove `Callback.source_result`. `_split` needs `function_parts` only for
  the source parameters; request no result from that lossy operation.
- In `_function`, pass `cb.source.apply()` unchanged to `_func_call`.
  The existing `convert_expression(call, cb.result)` must see the real type.
- Reuse the existing callback result-mismatch diagnostic. Do not introduce
  another conversion validator or change opaque foreign-header handling.

The exact declared-result comparison rejects qualifier differences that the
callback contract already excludes. It must preserve matching qualified
results and ordinary supported typedef equivalence. Do not propagate this
strict callback rule into general C assignments or calls.

**Verification.** Keep `callback-adapt-const-result` as the positive control.
Add one focused rejection fixture for const-source/mutable-target using the
existing diagnostic. Run `callback-adapt-return`, `callback-adapt-nullary`,
and `lambda-adapter-wide-return`, because emission is shared with lambdas.
The rejection fixture protects the compiler-generated thunk's type contract;
a permanent crashing-pointer test is unnecessary.

**Cost.** Replace existing comparisons, delete one record field and one
canonicalization. No extra runtime work or general type-system machinery.

## 4. Receiver-return summaries

**Change.** Add exactly these entries beside related operations in
`src/regions/runtime.x`:

```x2c
"Array_update_n": (summary 0 ((0 return))),
"Map_update_n": (summary 0 ((0 return))),
"Map_merge_with": (summary 1 ((0 return))),
```

The final `1` matters: a null receiver makes `Map.merge_with` delegate to
`Map.merge`, which can allocate a new receiver. The update operations return
the existing receiver. Reuse `_typed_families` for typed variants.

Do not extend the lifetime algorithm or attempt to prove unknown native
callees safe. The operation implementations already establish these facts.

**Verification.** Extend `region-returned-arguments` with returns through the
three operations and preserve its caller-owned receiver control. Extend the
existing `meta-heap-regions` rejection coverage to show the same facts become
errors under the existing meta policy. Runtime warnings and meta errors must
agree with the direct-return and `Map.merge` controls. No new diagnostic.

**Cost.** Three entries in an existing compiler table. No runtime cost, new
analysis pass, or new state beyond those entries.

## 5. Package license contents

Generated `autodiff-source.tar.gz` and `greet-source.tar.gz` currently contain
no LICENSE or NOTICE. Autodiff's README links outside its archive. This is
an artifact-content finding, not a legal assessment.

**Recommended small design.** Add ordinary copies of the repository LICENSE
and NOTICE to these nine released package roots:

- `packages/autodiff` and `examples/packages/greet`;
- `packages/pcre2`, `yyjson`, `libcurl`, `termbox2`, `libuv`, `blis`, and `torch`.

Preserve upstream `LICENSES/` contents. Make autodiff's license link local to
its package. Extend the existing metadata glob in `packages/tools/bundle`
with `NOTICE*`. Extend the root license row in `etc/x2c-payload.x` to copy
both LICENSE and NOTICE into the compiler's `licenses/` directory.

The source archiver and package installer already preserve these files, so
neither needs new logic. Do not use root-relative symlinks: the installed
package must stand alone. Producer-only injection would require another
source-archive staging path and still omit direct-directory installations.

**Tradeoff.** Eighteen copied assets add 102,609 uncompressed bytes of license
and notice text, plus two small copy-list edits and the README link correction.
This deliberately duplicates stable distribution material instead of adding
packaging code. There is no compiler/runtime performance cost.

**Verification.** Generate the two real source archives and inspect contents
and bytes. Use the existing scratch install cases to confirm retained files.
Inspect the compiler payload's `licenses/NOTICE`. Inspect the native package
archives during candidate preparation; do not rebuild every native dependency
merely to validate a metadata glob. No new license-audit framework or gate.

## 6. Regex: decision and bounded experiment

Two supported matching workloads crash: 60,000 consecutive `(a)` groups on
the main stack, and 2,000 nested groups matched on a 32 KiB task stack. Shallow
controls pass. The book promises catchable Regex depth errors on small stacks.

**Recommended experiment, if selected.** Add only the existing floor check at
entry to `_run` in `lib/regex.x`, reusing `m.floor` and `_too_deep`. Every
recursive match route reaches this owner. Retain `_iterate`'s existing depth
and floor protection initially. No new counters, limits, records, or API.

The check is per `_run` entry, not per byte in its internal loop. It also runs
at each attempted search offset and offered backtracking endpoint. Checks at
several recursive helper boundaries might avoid some comparisons, but add
placements and risk missing a path. Do not adopt that alternative speculatively.

**Focused evidence.** Reuse `unittest/test-regex.x` and the existing
`task_small_stack_bounds_library_recursion` test in `unittest/test-task.x`.
Require the reported workloads to stop through the existing size-limit error
and shallow controls to match normally. Use child time/core limits for probes.

Use a temporary paired probe against the unchanged baseline: compile patterns
once, then repeat matches for long byte repetition (`a*b`), repeated groups
(`(?:a)*b`), captures/alternation, failed backtracking, and long unsuccessful
literal search. Report workload counts, absolute baseline/candidate elapsed
times, run spread, and percentages. PCRE2 regex-redux is a different engine
and cannot measure this change. Do not add a recurring benchmark target.

**Gary's decision.** Choose the bounded measurement experiment or defer this
repair for the release. No measured performance result exists yet. If the
experiment has material cost or needs more machinery, return with the actual
tradeoff before acceptance. Deferral must explicitly acknowledge the gap in
the documented guarantee; do not silently weaken the contract or disguise the
crash as fixed. Other implementation work can proceed independently.

## 7. Version and final release evidence

Recommend **0.16.0**, subject to Gary's choice. The compiler still reports
0.15.1, that public release already exists, and the Unreleased notes describe
source and ABI breaks. Do not overwrite existing release identities.

After selection, change `Compiler.version` in `src/cli/requests.x`, both
version expectations in `unittest/probes/run-cli-boundary.sh`, and the
Unreleased heading/date in `docs/src/reference/release-notes.md`. Review the
upgrade instructions against the included changes. Do not replace historical
0.15.x references globally. Generated bootstrap changes belong to the existing
regeneration/publication procedure, not hand edits.

After shared integration, use one final source SHA and candidate identity for
native archive verification. The latest observed successful candidate remains
the older 0.15.1 source; current local tests are not its replacement proof.
The release owner coordinates the separate website deliverable.

The pipeline's installed-bundle checks cover PCRE2 and Torch, but not five
other released packages. Recommend bounded, one-time evidence using the
actual candidate compiler and matching candidate packages on their four
promised platforms:

| Package | Existing workload |
| --- | --- |
| yyjson | `packages/yyjson/examples/release-catalog.x` |
| libcurl | `packages/libcurl/examples/page-titles.x` with `tools/run-fixture.py` in that package for local HTTP input |
| termbox2 | `packages/termbox2/examples/game-of-life.x` with the existing `tests/run-life.expect` PTY procedure in a scratch layout |
| libuv | `packages/libuv/examples/process-report.x` |
| BLIS | `packages/blis/examples/page-rank.x` |

Install into an isolated prefix and compile copied examples outside the
checkout. Keep artifact identity, platform, commands, and results with the
release evidence. `packages/tools/check-bundle.sh` demonstrates the procedure
but installs the checkout compiler; it alone cannot prove the candidate's
compiler bytes. Reuse procedures without adding a new CI matrix or gate.
Unavailability of a target is missing evidence, not a demonstrated defect.

Publication remains the release owner's separate action after the final
candidate is selected and verified. Website checks and deployment are not
assigned to this implementation plan.

## Deferred work

Do not include these in the first implementation batch: deep List rendering,
CPP overflow policy, alias-collision consistency, included-header attribute
compatibility, first unopened-script hover, diagnostic location polish,
runtime Lisp explanation, lint tier/structured output, or Notes command
simplification. They remain recorded findings or improvements, not universal
safety obligations. Linux REPL dependency identity remains unverified.

Repair the obsolete optional native-module REPL probe before using that probe
as release evidence; it is not evidence that native-module loading is broken.
No computed-slot staging redesign or broader native ownership proof is part
of this plan.

## Implementation verification and delivery

Use existing focused fixture selection, for example:

```sh
unittest/compiler-fixtures/run.sh check --fixture call-pointer-arguments
```

Run the named affected fixtures and relevant existing unit cases after each
repair. This plan selects evidence for the work; it adds no recurring test
requirement, stage, or gate. Review authored changes for unnecessary checks,
repeated binding, and code that can be removed before submission.

Use shared-integrator PR delivery unless Gary explicitly selects another mode.
The integration owner performs the existing combined-tree publication checks
and generated refresh once. No broad rebuild or package campaign is required
for a private checkpoint. Final evidence must name the final tree, not this
planning baseline.

## Plan review

- Existing declarations establish callable types; normalization interprets
  those declarations instead of validating them again. Constructed dimensions
  use the same expression binder as ordinary syntax, without origin checks.
  Runtime methods already establish the three receiver-return facts.
- Reuse `normalize_declared_type`, `bind_syntax`, `_typed_call`, existing
  callback diagnostics, `_typed_families`, archive walkers, and copy lists.
  Delete the lossy callback result field/canonicalization. No lasting cache,
  representation, framework, or traversal is proposed.
- Changes use structural matches and existing x2c owners. License assets add
  text rather than a second packaging implementation. Ordinary call fast paths
  remain intact; the sole proposed runtime check is the optional Regex change.
- Proposed negative coverage is bounded: callback qualifier mismatch protects
  its generated thunk contract; meta receiver-return cases preserve existing
  compile-time lifetime errors; Regex exhaustion cases, if selected, protect
  the documented catchable failure. All reuse existing error owners. No new
  validator or diagnostic is proposed. Pointer/dimension fixtures are positive
  correctness cases; archive inventories inspect actual distribution outputs.
- Regex acceptance and release version are the outstanding decisions. Any
  material growth in runtime work, code, or caller obligations returns to Gary
  with alternatives instead of being treated as routine implementation.
