# Phase6 isolated application profile

Instrumented compiler: `/tmp/x2c-dual-phase6-profile`, SHA in candidate.sha256.
The phase5 binary is unchanged. One isolated native build used the preserved
phase5 compiler. instrumentation.patch dry-applies against captured phase5
sources (patch-check.log); full source snapshots remain only in /tmp.

run-profile.py translates the actual seven-file compiler corpus, exception
benchmark, and defer-try-cleanup fixture at the same absolute paths/home as
phase5. Three timed repeats plus one count-only repeat were run per corpus
mode; the fixture has three timed repeats. All 67 translations have identical
outcomes and raw C/H digests to the phase5 manifest. results.json preserves
per-run counts, timings and digests; commands.log preserves full logs. Native
intermediates are retained in /tmp/dual-phase6-profile-runs, not research git.

## Counts

| Workload | Actual try apps | Try snapshots | Macro_apply / invocation rows | Producer calls | All semantic transactions |
| --- | ---: | ---: | ---: | ---: | ---: |
| Seven-file compiler, default | 2 | 2 | 2 / 2 | 4 | 2119 |
| Seven-file compiler, live | 2 | 2 | 2 / 2 | 4 | 2124 |
| Exception benchmark, each mode | 4 | 4 | 4 / 4 | 8 | 265 |
| defer-try-cleanup fixture | 3 | 3 | 3 / 3 | 6 | 264 |

All three timed repeats agree with count-only mode. Counts are actual
applications, including synthetic tries, rather than lexical token counts.
All-transaction counts include existing parsing/macro transactions; only try
snapshot time is attributed here.

## Times

Milliseconds below are medians of aggregate workload spans across three runs.
Per-span ranges and every exclusive/inclusive metric are in summary.json.

| Workload | Snapshot inclusive | Scope symbols.copy child | Application inclusive | Application residual exclusive | Binding exclusive | Producer evaluation inclusive |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Compiler default | 1.720 | 1.025 | 1.313 | 0.632 | 0.302 | 0.132 |
| Compiler live | 2.541 | 1.811 | 1.397 | 0.694 | 0.292 | 0.126 |
| Exception default | 1.784 | 1.723 | 1.816 | 0.856 | 0.473 | 0.091 |
| Exception live | 1.734 | 1.661 | 1.885 | 0.898 | 0.478 | 0.106 |
| Fixture default | 1.196 | 1.151 | 1.674 | 0.747 | 0.464 | 0.079 |

Actual Macro_apply is 0.001-0.005ms per aggregate sample. Invocation-row
production medians are 0.185/0.207ms compiler default/live; template replace
0.066/0.071ms. Application residual includes free-call projection, origin
stripping, invocation Match extraction, freshening and unclassified work; it
must not be labeled Macro_apply cost.

Snapshot and application are disjoint intervals. Their actual per-repeat sums
have median 3.033ms [3.010,3.050] compiler default, 3.852ms [3.835,3.951] live;
3.649ms [3.373,3.756] exception default, 3.685ms [3.515,3.808] live; fixture
2.876ms [2.733,2.924]. Sum separately computed medians only for presentation,
not for exact accounting. nonoverlap-totals.json records actual sums.

These approximately 3ms measured default compiler intervals cannot explain
the phase5 aggregate approximately 85ms/+1.40% median difference. Most whole-
translation work is outside these intervals, and the earlier paired ranges
include noise. In particular, extended snapshots on 2119 ordinary transactions
are counted but not timed here. There is no whole-overhead attribution.

## Scope and exclusions

Monotonic timers form a stack; each span records inclusive duration and subtracts
instrumented child durations for exclusive duration. Nonoverlap application
accounting is residual + Macro_apply + invocation rows + template replace +
binding-exclusive + producer-evaluation-exclusive + native-producer-body.
Producer evaluation covers ordinary meta argument/evaluator work, including
_ensure_lisp if reached, then native dispatch/body as a nested child. It does
not separately attribute Lisp initialization or helper cold startup. Native
producer body is 0.012-0.018ms aggregate, not the whole slot evaluation.

Scope-symbol copy is a child of snapshot. Snapshot exclusive includes other
map copies and snapshot bookkeeping; those remaining operations are not split.
Transaction commit/rollback, parse-time preparation, frame/new-name allocation,
region/declaration/landing/cleanup computation, and all unrelated compiler work
are uninstrumented. Timers/counters perturb execution; clock resolution and
nested instrumentation overhead make tiny individual values unreliable.
Counts-only mode disables clock reads. No runtime exception performance or
whole-build speed conclusion follows from these diagnostic timings.

## Optimization recommendation

Scope-symbol eager copy is the largest measured single per-try snapshot child,
especially in the exception/fixture workloads. Investigate lazy first-write
staging in the EXISTING SymTxn and authoritative Sym mutation owners, preserving
original borrowed Map ownership on commit and nested rollback. Ordinary binder
writes must still trigger staging; never skip protection merely because this
particular body seems structurally harmless. Do not substitute an unrestricted
undo journal, second validator or try-only parallel transaction implementation.

This recommendation reduces a measured per-application cost candidate. It does
not promise to recover the aggregate 85ms difference, satisfy a three-lowering
budget, or reject other viable implementations. No optimization was implemented.
