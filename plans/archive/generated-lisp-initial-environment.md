# Generate shared Lisp algorithms from x2c

> Status: done
> Implemented 2026-09-20. Gary approved fixed primitive calls with public names
> replaceable and explicitly accepted the measured approximately 5 us (1.5%)
> session-startup cost. The full publication gate and stage-2 regeneration pass.

## Design

Author filter in etc/init.x and extract its canonical forms with the existing
x2c.comptime.lower operation. Assemble retained etc/init-core.xlisp and those
forms into checked-in etc/init.xlisp. Both existing consumers keep loading that
same artifact; startup never invokes a compiler to produce it. Delete the
handwritten filter and share three native aliases with the compiler. Equality guards lower directly
to Lisp equality, so runtime sessions need no extra truth-conversion helpers.

Generated filter retains Lisp truth (only nil is false), callback order and
exactly-once invocation, empty-list behavior, and public replacement. Rebinding
public car/cdr/cons no longer changes its primitive operations. Other helpers
are outside this first migration.

The existing bootstrap-refresh generates the artifact using the current
stage-0 compiler, then updates the embedded runtime before copying bootstrap
C/H. No extra recurring verification target is added. Repeat generation after
self-host rebuilding to prove output stability. Installation uses checked-in
artifacts, including on a fresh checkout.

## Validation and delivery

Extend existing Lisp coverage for filter truth, effects, primitive rebinding,
and public replacement. Reuse the wide-list test. Verify runtime Lisp.new and
cold dispatch translation. Compare six interleaved baseline/candidate runs for
runtime initialization, compiler startup, and whole-library/compiler translation.
Translation must remain within noise. Gary approved the measured session
initialization cost for this first port; it is not a blanket waiver for later
ports. Review the authored and
generated diff, then run the existing final publication gate and deliver to dev.

## Plan review

The typed AST and existing lowering own binding and Lisp emission. The generator
serializes their forms without another translator or validator. The generated
artifact replaces one handwritten algorithm. Shared primitive aliases retain one
owner; no evaluator, cache, compiler state API, or new diagnostic is added.
Tests protect existing truth/effect behavior and the approved rebinding contract.

## Measurements

Six interleaved comparisons after warmup used identical kernel binaries for
initialization and matching cold source trees for translation. Early generic
truth support cost about 50 us/session; removing that support through direct
equality-guard lowering reduced the cost to about 5 us. A lexical-capture
variant was slower and was discarded. No new evaluator or native API was added.

The current direct-public-name artifact measured 357.548 us baseline versus
362.815 us candidate for creating, initializing, and destroying one session
(measured in batches of 1000). The small increase repeats across variants and
is not being waived as noise. The translation comparison preceding the removal
of the private alias measured cold dispatch 201.375/201.960 ms, whole library
2089.521/2065.464 ms, and whole compiler 2869.900/2872.112 ms: within variation.
The original no-slowdown condition caught this cost; Gary explicitly accepted
it on 2026-09-20. This exception applies to this port.

## Publication validation

The combined gate passed 929 unit tests (20,369 assertions), compiler fixtures,
raw-symbol comparisons, self-host stage comparisons, and 68 documentation
output checks. Independent review approved source and generated deltas: only
the embedded standard environment and equality-guard lowering change behavior.
Stage-2 regeneration is byte-identical (SHA-256
`50beacb03872e260852f7d7dd0b66dc118beae8a36730cd008cbaa7d6ab05a80`).
The existing gate records init.xlisp as derived output alongside bootstrap C.

This delivers filter and the shared artifact path. The other 35 ordinary Lisp
function bodies remain in init-core.xlisp for subsequent bounded migrations.
