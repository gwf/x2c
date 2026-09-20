# Migrate suitable compile-time Lisp to x2c

> Status: done
> Implemented 2026-09-20 in ba4815dd, 1205437e and 71d63d4d, with
> generated-artifact integration in the closing commit. Accepted autodiff,
> cases and SDK ports; retained bootstrap owners under measured constraints.

## Intent and acceptance

Use ordinary x2c for compile-time algorithms without changing public macro
syntax or supported behavior. Retain evaluator/bootstrap primitives, native
bindings, operation-name tables, and necessary thin Lisp adapters. Runtime
Lisp examples and x2c macro templates are not migration targets.

## Production autodiff

Complete the 106-function pilot against lib/autodiff.xmacro: checkpoint
snapshot/replay, sibling differentiation, reverse do loops, and production
rejections. Preserve all five decorators, generated interfaces, declaration
order, and errors. Pass per-derivation state explicitly; thin Lisp wrappers
retain unit-session sibling registries and register before deriving a body.
Keep derivative construction lazy with one primitive vocabulary. Only switch
production after parity and timings pass. Then replace the duplicate pilot
with numerical checks importing production; preserve distinct lowering tests.

## Bounded helper ports

Move cases.* into system macros, preserving scopes/labels/transfers. Move
remaining statement/block/declaration/parameter/enum builders to shared meta
bodies while preserving Lisp and x2c entry points. Port dedent/location glue
only where simpler. Keep approved literal checks and rest adapters. Delete
superseded implementations, update documentation, and deliver independently.

## Retained Lisp and research

Keep var-tags parked under its existing measured condition. Probe ordinary
init-environment algorithms for dependency/startup cost before proposing
migration. Builtins/binding bootstrap require demonstrated simpler loading
and acceptable cost. No new state API, cache, evaluator, or bootstrap framework.
Finish with an inventory of remaining substantive Lisp and its rationale.

## Validation and delivery

Reuse autodiff suite/fixtures/examples and checked documentation. Preserve
control flow, checkpoints, siblings, errors, and registry isolation; add only
missing compatibility probes. Compare generated code. Measure at least six
interleaved baseline/port runs with equivalent toolchain/cache conditions:
representative AD consumers, whole-library/compiler, and relevant startup.
Accept only differences within observed noise; after bounded simplification,
retain slower candidates as research and report blockers. Use existing final
publication gates without adding recurring requirements. Root owns generated
artifacts and integration; separate implementation and compatibility agents.
Deliver accepted changes to dev. Site updates are site-only; release builds
and production promotion are separate actions.

## Plan review

Parsing, binding, typing, and compiler queries establish the facts consumed
here. Reuse those operations and canonical match/templates, adding no parallel
validators or new diagnostics. Delete duplicate algorithm owners. New helpers
must express a transformation or carry existing state at its correct lifetime.

## Initial-environment research

A bounded `filter` port into the existing meta preload works with a warm
prelude. Cold bootstrap fails: `lib/dispatch.x` calls
`var.tag.descriptor.count`, which needs `filter` during declaration collection
before the replacement can load. Six interleaved cold translations gave six
baseline successes and six candidate failures at that same missing binding.
Failure latency is not a performance result.

The same initial environment is embedded by `lib/lisp.x` and evaluated by
standalone `Lisp.new`. A runtime probe through its kernel/standard-source
sequence returns `(2 3)` with the original filter and reports an unbound name
without it. Compiler meta preload does not install runtime Lisp operations.
A second handwritten seed would retain duplicate ownership; a new loading
framework is outside this plan. The prototype was not integrated.

## Remaining Lisp inventory

- `etc/init.xlisp`: the shared compiler/runtime initial environment. Its 36
  ordinary function bodies include map/filter/foldl; list lookup and append;
  pattern matching, binder extraction and substitution; selectors; numeric
  and variadic wrappers. They are expressible algorithms, retained for the
  reproduced cold-bootstrap/runtime loading dependency above. Only filter
  was prototyped; the result is not a claim that every individual helper has
  identical dependencies. Evaluator macros remain Lisp forms.
- `etc/builtin-macros.xlisp`: built-in iteration, scope expansion, and class
  generation (declarations/defaults, constructors, field writers, equality,
  hashing and boxing/unboxing), used while parsing the meta implementation. No prototype established
  a simpler loading path, so this bootstrap owner remains unchanged.
- `etc/lisp-bindings.xlisp`: native-binding syntax construction and registration
  needed to build the Lisp runtime. Retained under the bootstrap boundary;
  operation signatures continue to come from compiler declarations.
- `etc/comptime.xlisp`: evaluator operations and native-name adapters consumed
  by lowered x2c (numeric conversion/truth, cells, frame state, collection and
  callback operations). Moving these through the lowering they implement
  would introduce a bootstrap cycle. Operation tables remain declarations.
- `etc/lisp-values.xlisp` and `etc/lisp-io.xlisp`: native binding declarations
  and operation names, not duplicate compile-time algorithm bodies.
- `etc/lisp-extras.xlisp`: optional runtime Lisp range/fib/subst and aliases;
  outside this compile-time migration, as are runtime Lisp examples/tests.
- `lib/autodiff.xmacro`: thin entry wrappers own the two sibling
  registries for the existing unit-session lifetime. Registration ordering
  stays at that boundary; derivative algorithms and per-derivation state
  live in x2c. Nine forward-name placeholders let mutually recursive
  helpers lower before their definitions; every placeholder is replaced
  before the decorators run.
- `lib/var-tags.xmacro`: the measured port remains parked; its existing
  acceptance condition is unchanged and no unsuccessful candidate is revived.
- `lib/system-macros.xlisp`: dedent and location adapters. Dedent already calls
  the x2c folding algorithm; replacing this short boundary would require extra
  compiler-surface declarations in consuming units. Location only combines
  the invocation file and line. Neither warrants an additional loading layer.
- `etc/compiler-sdk.xlisp`: invocation/source adapters and the approved
  literal argument checks preserve Lisp-facing diagnostics. The rest-argument
  call adapter in `etc/comptime.xlisp` preserves its Lisp calling convention.
- Lisp generated by `src/comptime.x` is the execution representation of x2c,
  not a separately authored migration owner. `.xmacro` syntax templates and
  native binding tables are likewise not algorithms merely due to syntax.

## Accepted-candidate measurements

Each comparison alternates baseline/port order, warms both sides, and records
at least six pairs. Other agent builds were paused during timed runs.

| Candidate / workload | Lisp median | x2c median | Interpretation |
| --- | ---: | ---: | --- |
| Autodiff: production suite + two examples | 1.958 s | 0.715 s | 63% faster; IQR 25/23 ms |
| Autodiff: whole library | 2.104 s | 2.118 s | Within noise; IQR 48/91 ms |
| Autodiff: whole compiler | 2.597 s | 2.595 s | Within noise; IQR 289/92 ms |
| Autodiff: ordinary startup | 29.644 ms | 29.720 ms | Within noise; IQR 0.604/0.638 ms |
| Cases: whole library | 2.119 s | 2.109 s | Within noise; IQR 80/96 ms |
| Cases: whole compiler | 2.677 s | 2.672 s | Within noise; IQR 265/230 ms |
| Cases: ordinary startup | 29.108 ms | 29.121 ms | Within noise; IQR 0.670/0.799 ms |
| Cases: importing consumer | 57.396 ms | 53.291 ms | 7% faster; IQR 1.674/1.698 ms |

Autodiff's three consumer C/H outputs are byte-identical. Cases' 182 library
and compiler C/H files are byte-identical, as is a focused scope/control-flow
probe. The system-macro suite differs only in bijectively renamed literal
cache identifiers; its strings, comments and other generated tokens match.

## Source-review follow-up

Keep autodiff's existing `ad_*` helper names with `meta static` visibility.
A trial style-only rename to `_ad_*` exposed the current lowering's
`_lower_pure` rule in `src/comptime.x`: underscore-prefixed calls are treated
as duplicable expressions. Stateful derivative helpers can then execute late
or repeatedly. Reverting that rename restores the required sequencing without
changing the compiler. The naming-sensitive purity issue needs a separate
compiler repair; this migration adds no evaluator or purity framework.

The remaining SDK builder port was measured separately from cases, with six
interleaved pairs after matching generated-interface validity:

| Workload | Lisp median | x2c median | IQR, Lisp / x2c |
| --- | ---: | ---: | ---: |
| Three SDK consumers | 86.801 ms | 85.419 ms | 3.300 / 1.202 ms |
| Whole library | 2.057712 s | 2.050936 s | 28.542 / 84.057 ms |
| Whole compiler | 2.570840 s | 2.571299 s | 45.521 / 79.168 ms |
| Plain startup | 26.919 ms | 26.592 ms | 0.566 / 0.792 ms |

No measured regression exceeds the observed variation. An earlier unmatched
run invalidated the candidate's interfaces by removing temporary transition
adapters after building them; its extra startup collection cost was discarded,
and both candidate sources and interfaces were rebuilt before the comparison.
The transition uses the existing `X2C_COMPILER` build override, then the normal
publication gate refreshes bootstrap. No adapter bodies are duplicated in the
final source.

The SDK consumer C/H files match exactly, as do all library/compiler artifacts
except the expected new meta builders in meta.c/meta.h and six aliases in
frontend.c. The existing nine-test system suite (20 assertions), SDK fixtures,
and a baseline/port non-enum diagnostic comparison pass. The diagnostic text,
location and value note match exactly.

Independent source review checked all 27 primitive derivative definitions and
19 existing diagnostic strings, plus checkpoint/do/sibling/control-exit and
state paths. It caught a pilot gap: increment/decrement normalization dropped
the original expression type, yielding zero derivatives for double operands.
The port now preserves that type; `autodiff-increments` covers prefix/postfix
increment and decrement in both modes. `autodiff-state` checks declaration
order and state reset across both/forward/checkpoint/reverse decorators.
Two-unit probes, translated alone and in both orders, preserve the baseline
rejection when another unit's differentiated sibling must not be visible.

## Publication validation

The combined `agent-pr-check` passed: 928 unit tests (20,348 assertions),
745 compiler fixtures (1,742 artifacts), 558 raw-symbol comparisons,
self-host stage comparisons, and 68 compiled documentation output checks.
Reviewed bootstrap changes are confined to meta.c/meta.h and frontend.c.
The final archived record is included in the exact-tree publication check.

Documentation/site output is deployed separately from the compiler candidate.
The existing staging install files and candidate metadata remain byte-identical;
production promotion is not part of this migration.
