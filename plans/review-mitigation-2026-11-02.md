> Status: active
>
> Gary requested this plan and dispatch to a new SOL 6.1 task on
> 2026-11-02. Implementation is authorized for the seven findings below.
> Review baseline: `dbcb6c3475732744cff6456880d707087cf79026`, fetched
> `origin/dev`. No repairs have been made. Delivery is ready PR submission
> to the shared integrator, not direct publication to `dev`.

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
