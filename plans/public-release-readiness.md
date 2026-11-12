# Public release readiness

> Status: code fixes integrated; non-site release preparation, 2026-11-07.
> Baseline: `68ebfece63702c3e1ecc249bd8bbd85e5997ad8f` from `origin/dev`.
> Four bounded compiler repairs, packaging, and version preparation are complete.
> Version 0.16.0 is prepared. Gary approved the minimal Regex repair.

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
Linux behavior. The verification above predates the repairs; submission evidence follows below.

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

**Implemented change.** Preserve the direct-signature paths and existing
`resolve_key` fallback. Only if a pointer still has no callable signature,
resolve its pointee typedef with `resolve_key` and use existing `apply`,
`function_parts`, and `_typed_call` operations.

This belongs in `_finish` in `src/expressions/calls.x` and `_call` in
`src/transform/expressions.x`. Result typing does not rewrite the callee's
source spelling, so both sites need the narrow interpretation.

The proposed `normalize_declared_type` replacement was too broad: it resolved
result identities such as `Var` into their underlying union and caused six
runtime-source build errors. The final repair preserves those identities.
No new resolver or global normalization was added. `_check_arity`, Iter
completion, and rest-call reconstruction are unchanged.

**Verification.** Extend `call-pointer-arguments` with the function-typedef
pointer form, integer boxing, and an expression that uses its String result.
Keep the existing pointer-typedef control. Require successful translation,
native compilation, and the expected output through the existing fixture.

**Cost.** Only unresolved pointer signatures take an extra pointee lookup.
Direct-call fast paths and calling conventions remain unchanged. No runtime
checks are added.

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

- In `_check_signature`, compare `cb.result.declared()` and
  `cb.source.apply().declared()` after `_x2c_type_unqualified` removes only
  outer copied-value qualifiers. Retain pointee qualifiers and semantic
  typedef identities; do not normalize them into underlying representations.
- Remove `Callback.source_result`. `_split` needs `function_parts` only for
  the source parameters; request no result from that lossy operation.
- In `_function`, pass `cb.source.apply()` unchanged to `_func_call`.
  The existing `convert_expression(call, cb.result)` must see the real type.
- Reuse the existing callback result-mismatch diagnostic. Do not introduce
  another conversion validator or change opaque foreign-header handling.

The comparison rejects pointee qualifier differences while preserving prior
acceptance of harmless outer copied-value qualifiers. Matching qualified
results and semantic typedef identities remain intact. General C assignments
and calls are unchanged.

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

**Approved minimal repair.** Add only the existing floor check at
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

**Measured result.** On macOS arm64 with Apple Clang 17 and `-O2`, seven
alternating pairs gave these match-loop wall-time medians. Pattern compilation
was outside the timed interval. Only `regex.o` and the archive symbol index
differ between the baseline and candidate runtime archives.

| Workload | Matches/run | Baseline seconds | Candidate seconds | Change |
| --- | ---: | ---: | ---: | ---: |
| `a*b`, 200,000 a bytes then b | 10,000 | 0.775520 | 0.864207 | +11.44% |
| `(?:a)*b`, 1,000 a bytes then b | 30,000 | 0.468654 | 0.448571 | -4.29% |
| Captures and alternation on abcd | 1,000,000 | 0.607531 | 0.600995 | -1.08% |
| Failed nested repetition on 12 a bytes | 2,500 | 0.468401 | 0.440687 | -5.92% |
| Failed literal search through 200,000 a bytes | 1,500 | 0.664949 | 0.591619 | -11.03% |

The first byte-repetition ranges were disjoint: 0.752949-0.786097 seconds
baseline and 0.810869-0.896394 seconds candidate. Reversing the first run order
for seven further pairs gave 0.759482 versus 0.837084 seconds (+10.22%), with
noisier overlapping ranges. These are elapsed-time measurements, not CPU
instruction counts or whole-compiler performance measurements.

**Generated-code investigation.** Generated C differs only by the floor check
and a diagnostic line number. Apple Clang 17 retains the same helper inlining;
the new floor helper also inlines. The hot byte loop has the same 15 ARM64
instructions, with a bound register and branch addresses changed. No per-byte
call or spill is added. The check executes twice per successful `a*b` match.
`_run` retains its 112-byte stack frame and grows from 1,404 to 1,428 bytes.
The original hot loop moves 96 bytes; register allocation and block placement
change. Lost inlining does not explain the observed slowdown.

Seven further rounds used the same 10,000-match workload, rotated/reversed
binary order, and a 1,000-match warmup. Scratch relinks shared one benchmark
object and baseline runtime archive, replacing only the Regex object. The
three relink controls had the same `_run` address and text-section alignment.
The alignment control pads before the hot loop without changing the repair.

| Binary | Median seconds | Minimum | Maximum |
| --- | ---: | ---: | ---: |
| Original baseline | 0.743023 | 0.694392 | 0.813299 |
| Original repair | 0.836799 | 0.694189 | 0.881090 |
| Controlled relink baseline | 0.758057 | 0.738796 | 0.849691 |
| Controlled relink repair | 0.758862 | 0.717880 | 0.909654 |
| Controlled relink repair, aligned loop | 0.764103 | 0.684650 | 0.791933 |

The original binaries differ by 12.6%; the controlled relinks differ by 0.1%.
Explicit loop alignment does not improve the checked relink median. Broad,
overlapping ranges limit precision. These results support code-layout
sensitivity, but do not isolate instruction fetch, cache behavior, or branch
prediction as the cause. A 64-byte boundary explanation is not established.
The initial 11% slowdown belongs to that binary pair and workload; it is not
established as an inherent cost of the repair. Nor do these results establish
zero overhead across workloads or platforms.

Both reported crashes become catchable size-limit errors; 31 focused Regex
and Task tests pass with 364 assertions. Production code changes by one line.
The existing error text describes a repeated group and can report limit zero
for the new floor failure. That diagnostic wording remains a known limitation;
Gary approved keeping the minimal repair without expanding it.

**Decision, 2026-11-07.** Gary approved including the unchanged one-line repair
and its focused tests in the release fixes. The initial release fixes merged
through PR #649; the Regex repair is a follow-up from that integrated revision.
No broader alternative, recurring benchmark target, or contract change is added.
Raw local evidence is retained in
`/tmp/x2c-release-regex-deb7/debug/regex-evidence/` and
`/tmp/x2c-regex-codegen-deb7-1107/`; the findings above are the durable record.

## 7. Version and final release evidence

Gary selected **0.16.0**. The compiler and CLI expectations now use that
version; the release-notes heading says `0.16.0 (unreleased)`. Existing
release identities remain unchanged.

The version preparation changes `Compiler.version` in `src/cli/requests.x`, both
version expectations in `unittest/probes/run-cli-boundary.sh`, and the
Unreleased heading in `docs/src/reference/release-notes.md`. Publication date remains unset. Review the
upgrade instructions against the included changes. Do not replace historical
0.15.x references globally. Generated bootstrap changes belong to the existing
regeneration/publication procedure, not hand edits.

After shared integration, use one final source SHA and candidate identity for
native archive verification. The latest observed successful candidate remains
the older 0.15.1 source; current local tests are not its replacement proof.
The release owner coordinates the separate website deliverable.

The pipeline's installed-bundle checks cover PCRE2 and Torch, but not five
other released packages. Gary approved bounded, one-time evidence using the
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

## Remaining release preparation and hold

Gary approved the five-package verification on 2026-11-07. Run it once on
all four promised platforms against the final candidate compiler and matching
archives. This is 20 package/platform cases, not a recurring gate or new CI
matrix. PCRE2 and Torch retain their existing release checks.

PRs #649 and #650 are merged. The reviewed source tip is
`ee8730a234b99428bda1345480cbbc456ae5fa25`, not a selected final candidate.
The release notes now include Regex. Upgrade instructions cover the existing
source/ABI changes, including explicit `$let`/`with` and alias migration rows.
Keep `0.16.0 (unreleased)` until the release date is known. No `v0.16.0` tag
existed at this review; recheck before tagging.

Staging and publication are explicitly held until the website session is
ready. Do not advance `main`, create a release tag, or dispatch staging or
promotion while that hold is active. The candidate workflow assembles complete
sites as well as native archives, so defer the final candidate selection and
build to the coordinated release owner. No candidate archive exists yet for
this source; current local tests cannot complete candidate verification.

The integration owner must retain generated-refresh and publication-gate
proof for the final tree. The merged PRs' focused evidence does not establish
that proof. Do not duplicate the broad gate here or generate website files.

### One-time installed-package procedure

Use the final candidate identity, full source SHA, manifest, and archive
hashes. On each of `darwin-arm64`, `darwin-x86_64`, `linux-aarch64`, and
`linux-x86_64`, install the matching candidate compiler into an isolated
prefix. Verify archive hashes against `candidate.json` before use. Take
examples and fixture helpers from that same source revision. Use Python 3,
`expect`, and the platform's normal compiler; record missing tools as blocked
coverage rather than silently substituting another workload.

Install the five matching native archives with that prefix's absolute
`bin/x2c install -q ARCHIVE` command. Do not use `make install`, the production
package index, checkout native build outputs, or `--force`. Copy each example
into its own scratch application directory outside the checkout and compile
there with the candidate compiler. Retain compiler version output, installed
package identities, build/run exit codes, stdout, stderr, and archive hashes.

| Package | Build and execution in its scratch application directory | Required observation |
| --- | --- | --- |
| yyjson | Build `release-catalog.x` with `x2c build -q --output program release-catalog.x`; run `./program`. | Exit 0; published service is `edge-api`, stable downloads are 2270, duplicate region entries are retained. |
| libcurl | Build `page-titles.x` as `program`; run `python3 run-fixture.py ./program` using the copied package helper. | Exit 0; guide, reference, and source titles match the helper's local HTTP responses. |
| termbox2 | Create `builds/`; build `game-of-life.x` as `builds/game-of-life`; run `expect run-life.expect` using the copied existing helper. | PTY sees a live cell, sends `q`, and observes exit 0 within its timeout. |
| libuv | Build `process-report.x` as `program`; run `./program`. | Both children exit 0, normalized output is ALPHA/BETA/GAMMA, line count is 3; PIDs vary. |
| BLIS | Build `page-rank.x` as `program`; run `./program`. | Exit 0, finite scores for all five pages, convergence before the 100-round cap; inspect numeric output rather than requiring identical floating-point text. |

Use the full installed compiler path in every build command above. The
`libcurl` helper starts and stops its own local HTTP server. The termbox2
helper owns its PTY and exits it; no desktop browser or interactive handoff is
needed. On macOS, use the existing `check-bundle.sh` linkage inspection to
check installed dylibs for build-machine Homebrew references, without running
that script's checkout compiler installation.

Retain one result row per candidate/package/platform, with command, expected
observation, actual output, status, and log paths. Inspect LICENSE and NOTICE
in these actual archives as well. Any failed case needs diagnosis against the
same bytes; rebuilding creates a new candidate and invalidates the old
candidate's verification. A missing platform remains explicitly unverified.

No package/platform row is marked passed yet. Execute this procedure after
candidate assembly; existing four-platform staging proof and final promotion
remain separate steps under the hold above.

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

## Implementation evidence

The release work branch contains the four compiler repairs, package notices,
and version 0.16.0 preparation. The compiler repairs add 28 lines and remove
12 across five source files. No helper, analysis pass, runtime check, or public
ABI was added by those compiler repairs. The approved follow-up adds the
one-line Regex floor check and focused regression coverage.

The combined tree passed `make build`, all eleven focused compiler fixtures,
`make command-artifacts`, and `unittest/probes/run-package-install.sh`.
The focused cases are call-pointer-arguments, macro-construction-regressions,
macro-argument-kinds, callback-adapt-result-qualifiers,
callback-adapt-const-result, callback-adapt-return, callback-adapt-nullary,
lambda-adapter-wide-return, region-returned-arguments, meta-heap-regions, and
iter-chain-pointer. The dimension counter and callback outer-value-qualifier
controls also pass in the isolated compiler repair.

All eighteen license/notice files match their repository owners. Both actual
source archives were regenerated on the combined tree and contain those
bytes. The installed probe checks the compiler payload, source installation,
and inert pure/mixed native bundles. No native dependency downloads were
needed. The CLI boundary probe passed on the version-preparation revision,
before the compiler repairs were combined; the version expectations remain
unchanged in the combined tree.

No new compiler capability is adopted by compiler/runtime source, so no local
bootstrap transition was required. Final bootstrap and generated-document
refresh, broad publication checks, actual platform archives, and website
integration remain the integration/release owner's work. No site files were
changed or site checks run during implementation.

The approved Regex follow-up starts at integrated revision
`2ecd835b7524145c57e33079cf1c3dec0e7fa4fc`. It passed `make build-safe`,
`make -C unittest test-all`, and both `regex_suite` and `task_suite` with scope
accounting enabled: 31 passed, 364 assertions, no failures or skips. The
production diff remains exactly the measured one-line check. No site files
changed. This is focused submission evidence, not final platform publication
validation.

## Plan review

- Existing declarations establish callable types; normalization interprets
  those declarations instead of validating them again. Constructed dimensions
  use the same expression binder as ordinary syntax, without origin checks.
  Runtime methods already establish the three receiver-return facts.
- Reuse `resolve_key`, `bind_syntax`, `_typed_call`, existing
  callback diagnostics, `_typed_families`, archive walkers, and copy lists.
  Delete the lossy callback result field/canonicalization. No lasting cache,
  representation, framework, or traversal is proposed.
- Changes use structural matches and existing x2c owners. License assets add
  text rather than a second packaging implementation. Ordinary call fast paths
  remain intact; the sole added runtime check is the approved Regex entry check.
- Proposed negative coverage is bounded: callback qualifier mismatch protects
  its generated thunk contract; meta receiver-return cases preserve existing
  compile-time lifetime errors; Regex exhaustion cases protect
  the documented catchable failure. All reuse existing error owners. No new
  validator or diagnostic is proposed. Pointer/dimension fixtures are positive
  correctness cases; archive inventories inspect actual distribution outputs.
- Gary approved the minimal Regex repair; 0.16.0 is selected. Any
  material growth in runtime work, code, or caller obligations returns to Gary
  with alternatives instead of being treated as routine implementation.
