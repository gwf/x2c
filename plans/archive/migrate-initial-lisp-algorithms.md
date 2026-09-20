# Migrate the remaining initial-environment algorithms

> Status: done
> Completed 2026-09-20; delivered with this migration commit.
> All remaining fixed-arity bodies use the shared generated artifact.

## Implementation

Use ordinary x2c for list traversal, numeric wrappers, selectors, predicates,
and pattern helpers. Preserve Lisp truth, callback order, tail/pair returns,
scalar final append arguments, pattern output, errors, and public replacement.
Fixed primitive calls follow the approved contract from the first filter port.
Keep distinct public callable identities where they were previously distinct.

Accumulate lowered definitions in the existing compiler session, serialize
those forms, and splice them into init-core.xlisp before aliases that need
those definitions. No second translator or retained handwritten algorithm.
Expose only the required existing native operations in the shared core. Avoid
compiler-only state and generic C lowering support in runtime Lisp sessions.
Retain the four rest-argument adapters and identity conversion at the boundary.

Separate agents implement pattern candidates and review compatibility. Root
owns integration, source deletion, generated artifacts, and publication.

## Validation and delivery

Reuse the Lisp suite in file-loaded and embedded modes, compiler fixtures,
whole-tree translation, and the existing publication gate. Add focused cases
for callback order, unusual append results, malformed selector inputs, callable
identity, and binder ordering. Compare at least six interleaved baseline/port
runs after warmup for initialization, cold compiler, library, and compiler
translation. Report aggregate cost; the previous startup exception applied to
filter, not an unrestricted slowdown allowance. Review the completed authored
and generated diff, regenerate through stage 2 to verify a fixed point, and
validate the final tree before delivery to dev.

## Plan review

Canonical typed functions and existing lowering establish the generated forms;
the generator only accumulates and serializes them. A declined lowering now
stops generation through the existing diagnostic operation instead of writing
an incomplete bootstrap artifact. This checks the producer's documented empty
result, not the AST again. Native aliases prevent a public adapter from calling
itself through the compiler prelude. New helpers express binder traversal or
preserve public callable identity; no evaluator, cache, state API, or new gate
is introduced. Tests cover observable compatibility rather than source shape.


## Remaining Lisp owners

- `init-core.xlisp`: evaluator macros implement evaluation/binding rules;
  native bindings and operation names expose existing runtime operations.
  `list`, `begin`, `append`, and `string-append` only adapt rest arguments.
  `List_var` preserves the lowering boundary's identity conversion.
- `init.xlisp`: checked-in generated bootstrap data shared by compiler and
  runtime, with no second handwritten algorithm body.
- Compiler prelude and built-in macro bootstrap: bindings and phase-sensitive
  setup remain outside this initial-environment port.
- Existing system-macro entry adapters and autodiff registries retain their
  argument conventions and compiler-session lifetime. Their algorithms
  already live in x2c.
- Var-tags remains subject to its separate measured acceptance condition.
  Runtime Lisp examples and emitted Lisp remain supported uses of Lisp.

## Candidate review

All 31 remaining fixed-arity bodies are authored in x2c; the four rest
adapters stay in Lisp. Independent review found and corrected shared callable
identity for `not` and `null?`. The shared algorithm now has a thin distinct
entry wrapper. The focused Lisp suite passes in both loading modes: 60 tests,
557 assertions. Short lexical lowering names retain the session-wide counter
and a non-C separator; globally defined loop helpers keep function suffixes.
Their only intended generated-code difference is spelling of lexical slots.
Gary accepted the aggregate startup cost and authorized committing the migration.


Six interleaved baseline/candidate pairs after two warmups, equivalent cold
compiler homes (median):

| Workload | Baseline | Candidate |
| --- | ---: | ---: |
| Initialize one Lisp session | 364.7 us | 470.4 us |
| Cold dispatch translation | 214.4 ms | 217.3 ms |
| Whole-library translation | 2275.6 ms | 2268.5 ms |
| Whole-compiler translation | 3011.6 ms | 3002.4 ms |

Translation differences are within observed run variation. Initialization
adds 105.7 us (29%), accepted for this migration. Publication validation
and delivery follow the existing gate. Raw local measurements are in
`debug/init-batch-timing.json`; baseline is 7afe67b6.

Publication validation passed: 930 unit tests (20410 assertions), 747 compiler
fixtures (1746 artifacts), CLI probes, self-host checks, and 70 documentation
samples with matching output. Stage-2 regeneration leaves the shared Lisp
artifact unchanged. The final archive metadata is included in the final gate.
