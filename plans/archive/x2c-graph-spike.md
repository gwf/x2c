> Status: done
> Spike and approved conditional-tail implementation complete, 2026-09-07.
> Implemented in d599dfd; broader walks changes remain deferred.

# x2c-graph spike

The tool works on current source. A fresh `make build-safe`, followed by
`make -C tools/x2c-graph test` and `make -C tools/x2c-graph run`, passed.
The source revision also matched the live remote main at the start. Main later
advanced to 885c1a1; x2c-graph, src/emit.x, and src/snapshot.x are unchanged
in that commit. Measurements below belong to the explicit 12a9a45 snapshot.

The rerun covers 72 authored compiler/runtime files: 3,592 functions and four
file-scope nodes, 12,680 distinct resolved direct-call edges, and 20,302 parsed
call occurrences. There are 1,263 external and 148 indirect call occurrences.
The datasets match the raw graph exactly and are byte-identical with reversed
input order. Individual whole-corpus analyses took 2.5-3.1 seconds.

## Findings

- `tail-calls` misses calls in the result arms of `?:`. The current
  `src/snapshot.x:63` `_function_type` is one such function. A temporary
  12-line Match case fixes the classification, increasing the current report
  from 25 functions/48 tail sites to 26 functions/49 tail sites. The entire
  existing graph test runner passes with the temporary binary. Focused probes
  cover ordinary and nested conditional returns, calls in the condition,
  arithmetic after the call, mixed tail/non-tail calls, and cleanup.
- `walks` yields 76 candidates, but its recursion heuristic marks every
  collection parameter traversed whenever the function calls itself. A tiny
  countdown function that never reads its List argument is reported as a
  walker. It also reports `NULL` as a collection to investigate. Parameter
  reassignment is another source of false reports: `Emitter._param` replaces
  `context` before traversing it, but forwarding attributes that traversal to
  its incoming argument. These are reasons to trace each candidate in source.
- Deleting blanket recursive inference and restricting roots to compiler
  `automatic` facts reduced the report to 53 candidates but still left seven
  emitter context groups. Restricting roots alone reduced it to 73 and lost a
  real Match capture in `_record_top_level_function_state`. Both shortcuts
  are rejected as fixes. Preserve recursive and Match-capture support until
  an argument-specific design is proved separately.
- `walks` did find one real simplification: `Emitter._commas` can replace
  `lst.len() <= 1` with `!lst.cdr()`. List.cdr already accepts nil. A temporary
  compiler generated identical bytes for 146 C/H files over 72 authored units
  plus generated lib/x2c.x. Profiling measured 31,210 calls and 21,188 avoidable
  cell reads. Five alternating timing pairs had medians 5.8524s/5.7922s with
  overlapping ranges. This is a small cleanup, not a proved speed improvement;
  pick it up when editing the emitter rather than start a performance project.
- There are no resolved lib-to-src calls. The graph offers no reason by itself
  to reorganize the compiler/runtime. `lifetime-escapes` reports zero findings,
  but examines only seven explicit regions; it does not establish memory safety.

Detailed outputs, validation script, exact invocations, and temporary probe
sources/patches are retained in `.context/x2c-graph-spike/`. Reproduce the
baseline reports after building with:

```sh
python3 .context/x2c-graph-spike/run.py
```

## Recognize conditional tail returns

Status: complete (2026-09-07), d599dfd.

The new fixture assertions fail with the original analyzer and pass with the
implementation. The full tool test suite passes. A fresh corpus comparison
on main 885c1a1 plus this change adds only `_function_type` at
src/snapshot.x:63, as the spike predicted. The implemented source reuses the
existing collector and adds no checks, helpers, or additional pass.

The approved implementation steps were:

Observable result: `tail-calls` reports a self-call returned by either arm of
`?:`, preserves non-tail classification in its condition and within arithmetic,
and continues reporting explicit cleanup.

1. Extend `_collect_tail_calls` in `tools/x2c-graph/x2c-graph.x` with one Match
   case for canonical `(op ? CONDITION TRUE FALSE)`. Visit the condition with
   tail=false and both arms with the incoming tail state. Reuse the existing
   collector, self-target resolution, source locations, counters, and blockers.
2. Extend the existing tail-calls fixture/assertions for the positive cases
   above and the adjacent non-tail classifications. Clarify conditional-return
   handling in the tool README. Do not change language acceptance or emission.
3. Run the focused tool tests and corpus comparison. The expected current
   corpus delta is only `_function_type` at src/snapshot.x:63.
4. Review and fix the completed authored diff for duplicate validation,
   unnecessary traversal/state/helpers, and idiomatic Match use. Then run the
   existing `tools/gate-state.py ensure agent-pr-check` before any publication.

The implementation changes only graph analysis, its existing fixtures, and
documentation.
The emitter cleanup and a wider walks redesign remain separate work. No new gate,
compiler API, graph format, runtime semantics, or recurring process is proposed.

## Plan review

The parser already supplies the canonical conditional AST and binding identity;
the collector already resolves exact self-calls and records cleanup. The new
case consumes those facts without validating their producer or reparsing them.
It reuses the collector and adds no helper, representation, cache, or second
pass. A Match pattern names the condition and result arms directly, and the
existing traversal handles their contents. This is ordinary x2c composition.
There are no proposed validators, dedicated diagnostics, or negative language
fixtures. The non-tail examples test analysis output for valid programs.
