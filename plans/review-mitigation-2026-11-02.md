> Status: active - implementation complete for all seven findings on
> 2026-11-02; publication remains with the shared integrator.
>
> Gary requested this plan and dispatch to a new SOL 6.1 task on
> 2026-11-02. Implementation is authorized for the seven findings below.
> Review and implementation base: `dbcb6c3475732744cff6456880d707087cf79026`.
> A fresh fetch before implementation found no intervening `origin/dev`
> changes. Delivery is ready PR submission to the shared integrator,
> not direct publication to `dev`.

# Repository review mitigation

## Outcome and boundaries

Repair four reproduced correctness defects, remove quadratic Regex capture
bookkeeping, make integration retirement recognize ordinary build outputs,
and reconcile contradictory guidance and active planning records.

Preserve public signatures, runtime representations, error causes, nominal
type behavior, and the existing validation workflow. Do not add a gate,
dependency, general arithmetic framework, allocator hook, or language
feature. The book owns semantics; old plan text does not override a later
deliberate decision. Keep unrelated work and historical evidence intact.

This plan does not commission the previously recorded Regex matching-stack
or deep List rendering repairs, HTTP symlink confinement, package-wide
changes, or deletion of speculative compiler residue. Those were not newly
proved repairs in this review. Keep their existing records and uncertainties.

## Baseline evidence

The review built stage 0 and independently reproduced each finding below.
The unchanged tree passed 1,201 unit tests with 104,036 assertions, 443
compiled book/site samples with 140 matching outputs, 66 curated examples
(62 run, four build-only), and 148 offline tool/configuration/release tests.
These results establish the baseline; they do not cover the missing cases.
Full compiler fixtures, native package tests, other hosts, live publication,
and browser rendering were not run.

Temporary probes may disappear. The reproductions below are sufficient to
recreate them. Review logs are under `debug/review-*.log` in the reviewing
worktree; sample logs are `/tmp/x2c-review-doc-*.log`.

## 1. Conditional result types

Owner: `src/expressions/operators.x`, `_conditional`; inspect the existing
numeric resolver, Type operations, destination conversion, and conditional
fixtures before editing. Read the Match guide for compiler work.

Reproduction:

```x2c
short a = 1, b = 2;
auto value = 1 ? a : b;
printf("%zu %zu\n", sizeof(1 ? a : b), sizeof(value));
value = 100000;
printf("%d\n", (int) value);
```

Current output is `4 2` then `-31072`, with a native truncation warning.
Also, with `int *a` and `const int *b`, `auto p = 0 ? a : b;` rejects
qualifier loss, while reversing the arms succeeds.

Apply integer promotions and usual arithmetic conversions to ordinary
numeric conditional arms even when their declared types match. Form the
proper compatible pointer result with combined pointed-to qualifiers,
independent of arm order. Reuse existing type owners; do not weaken
qualifier checking or special-case only `auto`. Preserve deliberate nominal
results, including Symbol conditionals, and existing Var arm conversion.

Add focused compiler fixtures for narrow scalar inference and pointer arm
order. Cover typedefs, const/volatile combinations, a null pointer constant,
and existing Symbol/Var/String conditional cases through relevant existing
fixtures. Confirm generated C compiles without new warnings and that meta
and runtime evaluation agree where the existing fixture supports both.

## 2. Empty Path glob

Owner: `lib/path.x:Path.glob`; regression owner: `unittest/test-path.x`.
`Path.glob("")` currently terminates with signal 11 because its String is
NULL when passed to `strpbrk`.

Return an empty List for an empty pattern before crossing the C boundary.
This follows the existing no-match contract and needs no new error cause.
Use one boundary case covering canonical empty String/NULL. Retain literal
path, wildcard, hidden-file, escaping, and trailing-slash coverage.

## 3. HTTP constructor failure ownership

Owner: `lib/http.x:HttpServer.new`; regression owner:
`unittest/test-http.x`. Logger owns detached sink storage and requires
`Logger.free`; closing the caller's Scope alone cannot release it.

Warm once, then repeat three times inside separately closed isolated
Contexts: `HttpServer.new(Router.new(), {host: "127.0.0.1", port: -1})`,
catching `bad-arg`. With `X2C_SCOPE_ACCOUNTING=1`, the current implementation
retains three scopes, twelve allocations, and 432 requested bytes.

Arm cleanup for each owned resource as construction acquires it, and transfer
ownership only after successful construction. Borrowed caller Loggers must
never be freed. Include failures after listener acquisition in the source
ownership review. Do not rely on the existing close method's channel guard
to clean a partially initialized server. Prefer established local defer or
catch cleanup patterns over a new lifecycle abstraction.

Test repeated deterministic invalid-port failure and successful close using
existing accounting support. Cover a supplied Logger remaining usable after
failure. Do not introduce allocation-failure injection infrastructure.

## 4. Linear Regex capture bookkeeping

Owners: `lib/regex.x:_add_capture`, parser construction, `_found`, `_capture`;
regression owner: `unittest/test-regex.x`.

Each capture currently appends to an immutable List, copying its entire
prefix. Repeated `(a)` patterns with 1,000/2,000/4,000/8,000 captures took
0.013151/0.042845/0.165479/0.688742 elapsed seconds in the independent review
run. Each input had a separate isolated Context; only compilation was timed.
These are observations, not calibrated benchmark medians.

Collect capture names in a parser-owned transient Array and convert once
after successful parsing. Preserve `Regex.capture_names` as a List and
preserve capture numbering, NULL names, and error behavior. Release temporary
storage on success and failure. Remove repeated List indexing when building
match results by traversing names once with their capture numbers; preserve
result order and whole-match capture zero. Do not change the matcher or its
stack policy as part of this optimization.

Verify named, unnamed, optional/unmatched, zero-capture, and nested captures
through existing tests plus a focused case where needed. Run paired baseline
and candidate compile measurements on the same capture counts, compiler
mode, and host. Report absolute times and multiple-run medians. Measure match
result construction separately if claiming its speedup. Keep the performance
probe optional and outside recurring gates.

## 5. Retirement and real build artifacts

Owners: `tools/integrate-dev.py:Queue.retire`,
`tools/test-integrate-dev.py`, existing build/clean definitions.

The current allowlist accepts `builds/` but rejects `bin/x2c`, bootstrap
objects, and generated header links. The existing disposable integration
harness passes retirement eligibility before these ordinary artifacts are
added, and rejects it afterward. Its build stub creates only `builds/0/x2c`.

Classify the actual generated products of the existing build and verification
targets. Reuse existing inventory/clean definitions where practical. Keep
classification narrow: do not allow every ignored file, all of `bootstrap/`,
or arbitrary include-tree content. Check expected symlink destinations when
recognizing generated links. Preserve refusal for unrelated ignored files,
pending changes, unique unpublished commits, and unresolved holds.

Extend the existing disposable tests with representative real output paths,
including bootstrap objects, compiler binaries, include links, and unit-test
products. Keep the negative ignored-note test. Test actual retirement only
in disposable fixtures; do not delete any user or integrator worktree.

## 6. Reconcile guidance and current work

Owners: `plans/deep-review-remediation-2026-11-01.md`, `plans/README.md`,
`agents/x2c-development-guide.md`; the orchestrator owns these shared files.

The earlier plan's batch C decision requires null iterator callbacks to fail
before consuming input. Commit `14e6fce147` deliberately changed that rule.
`lib/iter.x`, `unittest/test-iter.x`, and the iteration chapter now agree on
invocation-time failure. A map over range(0,3) with NULL callback constructs,
raises on its first pull, and leaves the source's next value equal to 1.

Record the superseding decision with its provenance. Keep the runtime's
current lazy behavior. Reconcile the plan index and completed batch records
against actual Git/PR evidence, leaving only unfinished work actionable.
Retain historical decisions as history; do not erase plan evidence.

The development guide prohibits declarations in `#if`, although
`lib/thread-state.x` and `generate-moved-body-define` use them. Replace the
blanket prohibition with a link to the language reference's conditional-arm
rules. Do not copy a second full semantic specification into agent guidance.

Run the existing documentation checks. No new prose lint or recurring
consistency gate is needed. Do not rewrite unrelated skills or playbooks.

## 7. Duration fractional scaling

Owner: `lib/time.x:Duration.scale`; regression owner: `unittest/test-time.x`.
`Duration.new(1000000000000000002LL).scale(0.5)` currently returns
500000000000000000 ns instead of the exact 500000000000000001 ns.

Preserve the integer nanosecond representation, existing exact integral-factor
path, nearest-nanosecond rounding convention, and `conv-range` failures.
Eliminate the intermediate conversion through double seconds. Treat the
supplied double as its exact binary value; do not promise decimal-rational
interpretation of an inexact double.

Use bounded private arithmetic to retain the integer count's significant
bits when applying the factor. Binary64 is already a runtime premise in
`lib/common.x`. Decomposing a finite factor into its binary significand and
exponent permits an exact integer product followed by one rounding step.
Prefer existing numeric operations; inspect whether a small local split-word
product is necessary. Do not assume long double is wider than double on all
supported hosts, introduce a bigint dependency, or add compiler syntax for
this repair. If the exact portable repair requires a material arithmetic
subsystem or exceeds the repository's proportionality boundary, present the
concrete alternatives and cost to Gary before that expansion. Keep this item
open; do not quietly weaken the documented precision to finish the batch.

Test the reproduced half, negative counterparts, tie rounding, subnanosecond
results, zero, nonfinite factors, and values near both signed limits. Use a
small independent exact oracle in an optional development probe if needed;
the permanent tests should express meaningful boundary behavior. Do not alter
Duration.seconds or Time.from_unix semantics incidentally.

## Implementation ownership and delivery

1. Read current root guidance and the orchestration skill. Use the existing
   review worktree `/Users/gary/.codex/worktrees/da20/x2c` as the task's
   coordinator, after inspecting its state. The new task may start in the
   registered project directory; explicitly change to this worktree first.
   Preserve this plan. Fetch `origin/dev`, compare intervening changes, and
   record the exact implementation base. Reproduce before editing; a repair
   already landed needs evidence and closure rather than another patch.
2. Establish `orchestrator`/`pr` context. Delegate independent work in isolated
   worker worktrees under the skill's existing rules. Suggested assignments:
   conditional typing; Path/HTTP/Duration correctness; Regex bookkeeping;
   retirement tooling. Shared guidance and this plan stay with the
   orchestrator. Workers use `worker`/`private`, supply focused evidence and
   commits, and never push, gate, or merge dev. Respect available concurrency.
3. Use fix-x2c-bug for defect diagnosis and execute-x2c-plan for settled work.
   Keep one coherent reviewable commit per connected repair where practical;
   private checkpoints require no broad gate. Rebootstrap locally only when
   needed to consume a compiler capability.
4. Collect and verify private handoffs. Run the relevant existing suites and
   compiler fixtures against the combined tree. Rerun full units when useful
   for the combined runtime changes; do not duplicate broad publication
   checks across workers. Update STATUS only where its recorded gaps change.
5. Review and fix the completed authored diff before publication validation.
   Check ownership, public compatibility, diagnostics, generated-file
   boundaries, performance evidence, and each acceptance case above. Record
   unfinished items explicitly. Do not claim that a green suite proves a
   repair whose reproduction was not checked.
6. Submit ready PRs targeting dev with the starting revision, exact head,
   dependencies, focused evidence, and relevant measurement records through
   `tools/integrate-dev.py submit`. Prefer a coherent combined submission;
   a genuinely unresolved Duration design may remain a named follow-up while
   independent completed repairs are submitted. The shared integrator owns
   final generated artifacts, performance checkpoint, publication gate, and
   remote dev publication. No direct delivery was requested.

## Design review

The repairs belong to existing owners: expression result typing, a native
path boundary, constructor resource transfer, capture accumulation, build
artifact classification, current guidance, and Duration arithmetic. They
require no new public concepts. Regex keeps its public List representation;
HTTP keeps borrowed/owned Logger distinctions; retirement retains its
preservation checks. Existing tests gain regression cases instead of another
validation layer. Duration's portable exact arithmetic is the one bounded
implementation question requiring cost review if a small repair is not
available. This plan authorizes the listed work, not broader architecture.


## Implementation evidence (2026-11-02)

All seven findings are implemented in the combined submission. The original
baseline evidence above is historical. No item needs a new design decision.

| Item | Result and focused evidence |
| --- | --- |
| 1. Conditional types | Narrow inference now prints `4 4`, then `100000`. Pointer qualifiers combine in either arm order, including typedefs and const/volatile pairs. The new `conditional-result-types` fixture checks runtime/meta parity, null arms, Symbol identity, and baseline-supported inferred String/Label member calls and both empty-string printf fallbacks without native warnings. |
| 2. Empty glob | The original signal-11 input now returns an empty List; `test-path` retains its existing path-pattern cases. |
| 3. HTTP ownership | Three warmed invalid-port failures retain zero scopes, allocations, and bytes, against baseline totals of three scopes, twelve allocations, and 432 bytes. Tests cover successful close and a borrowed Logger remaining usable. Acquired Logger, listener, and channel each have rollback until construction succeeds. |
| 4. Regex captures | Parser names use one transient Array and one List conversion. Match results traverse names once. Named, unnamed, nested, unmatched, and zero-capture cases pass. Paired compile measurements are below. |
| 5. Retirement | Disposable retirement accepts bootstrap objects/archives, compiler binaries, expected include links, unit products, and example check build directories. Unrelated ignored files, unexpected links/objects, unique commits, pending changes, and unresolved holds keep their refusal paths. |
| 6. Guidance | PRs #644, #645, and #647 are confirmed merged and their merge commits are ancestors of the implementation base. The earlier plan and index distinguish published batches from the final carried list. Iterator callback decision `14e6fce147` supersedes the old eager rule. Preprocessing guidance links to the reference. |
| 7. Duration | The reproduced half is `500000000000000001` ns. A 47-line private split-word product/rounding helper keeps exact binary64-factor arithmetic without another type, dependency, or public API. An independent exact-rational oracle on the combined tree matched 15,102 boundary/random pairs. |

Paired Regex compilation medians, elapsed seconds:

| Captures | Baseline | Candidate |
| ---: | ---: | ---: |
| 1,000 | 0.011239001 | 0.000099000 |
| 2,000 | 0.044695000 | 0.000193001 |
| 4,000 | 0.179978999 | 0.000406001 |
| 8,000 | 0.748367000 | 0.000848000 |

Each median has 15 samples: three alternating baseline/candidate process
pairs, each with five iterations. The same Darwin arm64 host, Apple clang
17, optimized mode, and probe compiled repeated `(a)` patterns in isolated
Contexts. Only `Regex.compile` was timed. No separate match-result speedup
is claimed. The optional probe and CSVs remain under `/tmp/regex-capture-*`.

Combined validation:

- `make build` and `make -C unittest test-all` passed.
- From `unittest/`, `X2C_SCOPE_ACCOUNTING=1 ./test-all` passed 1,205 tests
  and 104,084 assertions, with no final scope leak report.
- The seven fixtures `conditional-result-types`, `conditional-arm-types`,
  `conditional-string-arms`, `meta-destination-conversion`,
  `function-to-func`, `qualifier-void-pointer`, and
  `member-qualified-reference` passed without new native warnings.
- `python3 tools/test-integrate-dev.py` passed all 61 tests. After adding
  the example-output cases, the two affected disposable retirement tests
  passed again. The classifier also recognized the coordinator's complete
  2,807-file ignored inventory before submission notes were added.
- `make doc-check` passed the documentation and generated-text checks.
- `git diff --check` passed.

Full logs are retained as `debug/mitigation-*.log` in the coordinator
worktree. The first full-unit invocation from the repository root aborted
because the Lisp fixture reads `../etc/init.xlisp`; running from `unittest/`
fixed the invocation. Combined verification also found and corrected a
missing `Logger.free` in the new borrowed-Logger test before submission.
The final documentation check exposed String identity loss in pointer
joining. The corrected join retains the left typedef only when its full
normalized pointer type equals the result. Destination conversion continues
to own arm conversion; eager conversion changed raw C varargs empty-string
fallbacks, which the combined Diff suite caught. Baseline-supported String
and Label member calls and both empty-string printf fallbacks now have
regression coverage.

Authored-diff review confirmed existing numeric/type owners, immediate
qualifier merging without stripping deeper qualifiers, constructor resource
transfer, transient Array cleanup, and narrow generated-output recognition.
The new negative cases preserve existing range failures and retirement's
file-preservation boundary. No new diagnostic, recurring gate, matching
policy, public signature, or generated artifact is introduced.

The full compiler fixture suite, native package tests, other hosts, final
bootstrap regeneration, publication gate, and performance checkpoint were
not run here. The shared integrator owns the final combined publication
checks. Existing Regex matching-stack and deep List rendering follow-ups,
and the earlier plan's final carried findings, remain outside this repair.


## PR 648 review corrections (2026-11-02)

The review found three gaps at submitted head
`20dd175bd7d6ce62a97b305c27aa742c9291f1c8`. PR 648 was still open.
Readiness was withdrawn before edits; the queue reported no active batch.
All three reproductions were confirmed before repair.

- Numeric nominal identity: a conditional over two `Number` values backed
  by `int` selected the integer String converter and rejected `Number.value`.
  The numeric join now retains a matching declared type when the arithmetic
  result equals its resolved numeric type. Actual integer promotion or
  widening still changes the result. This replaces the Symbol-only exception
  and preserves the original narrow-scalar repair. The existing fixture now
  checks both the inferred method and destination converter.
- Void-pointer null constants: `(void *)0` previously forced an `int *`
  result to `void *`. The existing `_null_literal` owner now recognizes a
  zero integer literal cast to `void *`, including grouping, before pointer
  joining. The fixture dereferences results in both arm orders, with both
  plain and const pointees, and retains its `0` and `NULL` cases.
- Retirement binary names: `feature+test` is a valid Git branch, but the
  classifier rejected its compiler and `bin/x2c` link. Both filename checks
  now accept the build's nonempty single-component suffix contract. Existing
  regular-file and symlink destination rules stay in place. Disposable tests
  cover `+` and `@` suffixes, traversal links to an existing binary, and an
  unrelated ignored note.

The three reported compiler probes now print `nominal`, `1`, and `7`.
Completed authored-diff review found no new type owner, constant evaluator,
branch-name validator, public API, or recurring check. Destination conversion
still owns String canonicalization. No final bootstrap artifacts changed.

Correction validation on the combined tree:

- `make stage-2` passed, including compiler stages 1 and 2 with strict
  warnings. No local rebootstrap was needed. This applies the updated
  shared-integrator submission requirement; it is not a publication gate.
- The seven focused compiler fixtures listed above passed without new native
  warnings. The extended fixture includes Number method/converter checks,
  void-pointer null constants, String/Label methods, and empty-string printf
  fallbacks.
- All three focused disposable retirement tests passed.
- The full accounting-enabled unit suite passed 1,205 tests and 104,084
  assertions with no final leak report.
- `make doc-check` and `git diff --check` passed.

One earlier full-unit run stalled in `net_descriptor_handoff` while polling
for acceptance. Its cause is unknown. The owned process was sampled and
stopped; standalone network suites then passed on the prior runtime worktree
and corrected candidate. A complete repeat passed. Logs and the stack sample
are retained under `debug/pr648-*`; this does not claim a network repair.

The publication gate, final generated artifacts, performance checkpoint,
full compiler fixture suite, native packages, and other-host validation
remain with the previously stated scope and integration ownership.


## Second PR 648 review corrections (2026-11-02)

At reviewed head `5fcd486d093a1145de1a597c16f7b26d31c3fb88`, the
void-pointer pattern's bare `*` was a sequence wildcard. It admitted both
`void` and multiple pointer levels. The reviewed compiler printed `77` for
`Func(read_optional)((void)0)` where baseline translation raises
`<bad-types>`. Typedef and arithmetic-zero pointer casts also reproduced
native dereference failures; the baseline versions both print `7`.
Readiness was withdrawn before editing. The PR was open and the queue had
no active batch.

The shared expression helper now takes its existing Compiler context. A cast
qualifies as a void-pointer null constant only when
`Sym.normalize_declared_type` matches `%((!quote *) void)` exactly and its
operand is a recognized constant integer zero. Thus aliases use the same
Type owner, with no extra pointer level or void-valued argument accepted.

The syntax recognizer admits only supported constant integer forms before
calling the existing `Compiler.meta_argument` arithmetic decoder. Literal
and cast leaves use `Compiler.folded_constant`; casts also require eligible
operands, preventing pointer or call syntax from becoming an integer
constant merely because the decoder can recover a zero value. Names and
calls never reach arithmetic evaluation. No program code runs to decide
whether an expression is constant, and no new constant evaluator is added.

All three expression-helper consumers use the Compiler context: conditional
pointer joining, optional-reference operator admission, and dynamic Func
argument preparation. The independent recognizer in
`src/compiler/binding-facts.x` remains unchanged. Admission of an equality
operator is not a presence proof; its existing literal/NULL guard and
narrowing behavior is preserved rather than expanded.

The new `conditional-null-consumers` fixture checks that `(void)0`,
`(void **)0`, `(void *)zero` for a runtime variable, and
`(long)(void *)0` remain rejected as dynamic optional-reference arguments.
An independent baseline translation also rejects all four with
`<bad-types>`. Literal, typedef, and arithmetic-zero void-pointer constants
retain absent-reference behavior. `_Generic` checks confirm that runtime
zero casts keep the ordinary `void *` conditional result in both arm orders.

`conditional-result-types` now dereferences results beside typedef and
arithmetic-zero pointer casts in both arm orders, including const pointees.
It retains the narrow scalar, Number method/converter, Symbol, String/Label,
and empty-string printf cases from the previous corrections.

Validation of the corrected combined source:

- `make stage-2` passed with strict compiler stages 1 and 2; no local
  rebootstrap was required (`debug/pr648-second-final-stage-2.log`).
- Fourteen focused fixtures passed without native warnings: the two
  conditional regression fixtures, the original six related fixtures, and
  six optional-reference/operation fixtures. Exact results are in
  `debug/pr648-second-final-fixtures.log`.
- `make -C unittest test-all` completed. The full accounting-enabled unit
  suite passed 1,205 tests and 104,084 assertions, with no final scope leak
  report (`debug/pr648-second-units.log`).
- The reported typedef and arithmetic-zero standalone programs print `7`;
  the reported void-valued Func argument again raises `<bad-types>`.
- `make doc-check` and `git diff --check` passed.

Coverage is bounded by the current arithmetic decoder. Integer literals,
grouping, negation, supported binary arithmetic/comparisons, and decodable
integer casts are recognized. Other C11 constant-expression forms, including
unsupported unary/logical forms, sizeof, and enum names, remain unknown;
this is not a complete C11 integer-constant-expression implementation.
No presence-proof expansion, runtime library change, publication gate,
final bootstrap refresh, native package test, or other-host check was added.
The shared integrator retains final publication ownership.
