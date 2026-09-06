> Status: done
> Implemented September 6, 2026, in the fixed-shape Match emission change.
> Final publication evidence is recorded with the associated pull request.

# Fixed-shape Match emission

Keep the symbolic calculator benchmark unchanged while reducing repeated Match
execution cost. Limit the first implementation to static patterns consisting
of one literal Symbol head followed by unique named single-element binders.
The four calculator patterns have total lengths 2, 2, 3, and 4.

## Experiment and evidence

The current generated evaluator dispatches on its head Symbol, then invokes
`x2c_match_site_try_capture` for every visited node. The prepared pattern is
already cached; this is repeated machine execution, not repeated parsing.
A three-second sample found Match machine execution, SymbolSet lookup, and
Var decoding prominent.

A disposable copy of the generated calculator C replaces only those four
calls with fixed-length List checks and raw Var captures. No benchmark source,
compiler source, runtime source, expected output, or tracked timing changed.
Six measured runs after one warmup, rotating execution order, at one million
iterations produced these medians:

| Implementation | Milliseconds |
| --- | ---: |
| Existing symbolic evaluator | 584.60 |
| Direct-check probe | 151.65 |
| Existing fixed-node x2c evaluator | 12.02 |

All runs produced 111000000. The probe improves this evaluator about 3.85x,
but remains about 12.6x slower than fixed nodes. These are fresh x2c-to-x2c
measurements, independent of the stored C baseline. They do not establish a
compiler-wide speedup.

The same helper agreed with `x2c_match_try_capture` on 288 cases: four
patterns, subject lengths zero through five, four payloads (void, typed nil,
integer, nested List), and three heads (correct Symbol, wrong Symbol,
integer). On successful matches every captured Var bit pattern agreed.
The void probe used noncanonical stack nodes and does not establish a public
List guarantee: ordinary Lists forbid void cars. The committed regression uses
canonical Lists with typed nil, zero, integers, and nested Lists instead.

Probe artifacts are under /tmp: x2c-calculator-flat-raw.c,
x2c-calculator-flat-raw, x2c-calculator-flat-differential.c, and
x2c-calculator-flat-differential. The profiling sample is
/tmp/x2c-calculator-sample.txt. These are experimental artifacts only.

## Compiler implementation results

The unchanged calculator now receives direct checks from the compiler for
all four arms. Six rotating measured runs after warmup gave 588.89 ms for
the original executable, 155.35 ms for the new compiler output, and 12.05 ms
for the fixed-node version, each with checksum 111000000. The measured
speedup is 3.79x; the source benchmark is unchanged.

Generated calculator C grows from 5,503 to 6,520 bytes. With the same harness
compile/link flags and runtime archive, its executable shrinks from 393,080
to 392,936 bytes. Translating the same 27 compiler source files with the
pre-change bootstrap compiler and the new stage 0 takes median 3.392 and
3.382 seconds respectively (three runs after warmup); no material translation
time difference is demonstrated. Their emitted C/H totals are 1,867,213 and
1,897,030 bytes. This is a bounded local comparison, not a general speed claim.

The optimized calculator sample is now dominated by Var decoding/type checks,
SymbolSet lookup and evaluator work; Match machine execution no longer appears
among the major costs. This does not justify broader pattern specialization.

The existing unit suite passes 738 tests. An initial invocation from the wrong
working directory could not locate the Lisp initialization file; invoking it
from unittest resolves that error. Source review preserved existing local
binding/body emission and fallback matching, and replaced the invalid void
List regression with canonical values. The generated stages agree after refreshing the bootstrap through the normal
target. One C fixture, match-brace-free, intentionally changes from a runtime
call to the direct zero-capture check. Final publication proof is the
repository agent-pr-check command; its exact-tree result is recorded in the PR.

## One proposed pull request

1. Extend the existing typed-pattern inspection beside
   `Compiler.match_pattern_is_static` and `match_pattern_head_symbol` to
   recognize the narrow subset. Reuse `_match_pattern_value` and the existing
   analyzed binders. Do not add a second binder parser or diagnostic. Reject
   specialization (not the source) for repeated binders, stars, anonymous
   wildcards, nested patterns, dynamic values, non-Symbol literals, and guards.
2. In `Emitter._match_if`, emit direct node-existence, literal-head identity,
   and final-tail checks for eligible arms. Copy captured Vars into existing
   positional storage and reuse `_make_local_binders`, existing body emission,
   cleanup barriers, and head dispatch. Keep checking the literal head because
   failed arms fall through; a switch label alone is not proof for every arm.
   Keep general runtime matching unchanged for all other patterns. Do not
   expose a new runtime API or add a second cache.
3. Extend the existing Match statement tests with exact-length and unusual
   capture cases. Retain subject-once evaluation, first-match arm priority,
   shadowing, break/continue, and fallback behavior. Compare with the runtime
   matcher for success and capture values. Capture presence depends on node
   existence, not the truthiness of its Var. Internal transient capture writes
   must not become visible to a failed arm or change the public runtime's
   atomic-capture guarantee.
4. Generate the unchanged calculator through the modified compiler, inspect
   the emitted path, and repeat rotating timings with the same inputs and
   checksum. Run existing focused Match tests and fixtures. Record code-size
   impact and a compiler self-translation comparison to detect spillover cost.
5. Review and fix the completed authored diff for duplicate inspection,
   unnecessary state, unsafe positional access, and drift from existing
   emission conventions. Then regenerate affected artifacts through normal
   targets and run `tools/gate-state.py ensure agent-pr-check` on the exact
   final tree before one PR to main.

Public Match syntax and semantics do not change. Update the user-facing Match
implementation explanation only where it currently implies every statement
must execute the runtime matcher; keep semantic rules in the book. No new
mandatory gate, benchmark, flag, or runtime dependency is proposed.

## Plan review

The typed pattern producer and existing capture analysis establish static
values and valid binders. The classifier selects an optimization subset; it
must not duplicate validation or reject otherwise legal patterns. The subject
is still arbitrary List data, so node existence, literal identity, and exact
length are required to decide a match, not defensive revalidation.

Reuse the typed pattern inspection, head dispatch, capture storage, local
binder declarations, and arm/body emission. Eligible arms lose their static
MatchCaptureSite and runtime invocation. No persistent metadata, cache,
matcher runtime helper, or parallel semantic representation is needed.

Structural eligibility should use the existing canonical pattern value and
binder list. Direct node access belongs only in generated C for the measured
primitive operation; authored x2c remains a Match expression. The experiment
does not justify rewriting the benchmark to fixed nodes.

No new validators or dedicated diagnostics are proposed. Negative subject
cases preserve deliberate Match behavior: wrong shapes must fall through,
not select an arm or expose captures. Existing runtime semantics remain the
oracle. The measured speedup supports implementing this narrow optimization,
not broader pattern lowering without separate evidence.
