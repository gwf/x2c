# Combined isolated try proof

The stable compiler `/tmp/x2c-dual-combined-final` was built only from the
isolated `dual-macro-match-probe` checkout. Its SHA256 is in candidate.sha256.
No bootstrap refresh, commit, publication, or production rewrite was performed.
The incremental patch is against the preserved phase3 corrected bound-hole
control; existing parser/capture/Match experiments remain prerequisites.

## Actual application path

`_try_block` obtains `$compiler_try_shape` as a Macro value and calls
`shape(arguments)`. The existing Macro postfix parser emits ordinary
`Macro_apply`; this prototype operation returns a transparent source carrier
containing the pending invocation. `Compiler.bind_syntax` uses the existing
`_sdk_template_call` / `_capture_row` invocation producer, then the existing
macro expander and ordinary binder. The client does not read macro descriptors
or result envelopes.

The parsed compiled-in body contains `$Prototype_frame($frame)...` and
`$Prototype_cleanup($cleanup)...`. These remain canonical macro-slot/meta-call
forms, evaluated through evaluate_macro_slot -> _evaluate_meta_value ->
_meta_call_value inside the active macro expansion. A bounded native dispatch
for four named pure producers sits in that existing call owner. It receives
the ordinarily evaluated argument and returns data; it does not query Compiler
and does not pretend to demonstrate generic project-helper execution.
Compile-time producer callees retain definition-environment meaning.

Every input carrier is explicitly marked at its compiler-producing boundary:
frame and runtime-reference calls bound; declarations/body/landing/cleanup
lowered; template skeleton source. The private Prototype_* wrappers expose
producer facts in this proof, not a proposed public stage-getter family.
No stage is inferred from AST List shape. Carriers retain ordinary AST payloads;
there is no second binder or syntax-origin authentication.

## Effects and existing owners

- new-name: pure Prototype_name produces the allocation request. `_rewrite`
  consumes it at exactly the previous frame allocation point before recursive
  body lowering. The consumer delegates to fresh_name and sym.introduce.
- cleanup: parsed Prototype_cleanup returns code plus placement data. The
  consumer places the existing lowered cleanup and sets needs_exception.
  Existing region cleanup computation and exception placement remain owners.
- early: parsed Prototype_early returns an actual static declaration and memo
  request. The consumer uses add_early and names.adapters. Ordinary try has no
  new file early declaration, so this effect is exercised only by the separate
  opt-in probe, not represented as an empty early request in corpus runs.

The native call adapter is internal proof scaffolding. The meaning of its
capture carrier index is not a frozen public ABI. Runtime references in the
try skeleton are already-bound inputs; this proof adds no open-name hygiene
or lexical scope retention.

## Transaction proof

SymTxn stages adapters and base binding maps, restores original borrowed map
owners on commit, and snapshots append lengths for early_decls, inits, origins,
plus scalar origin and needs_exception. Existing counters/next_binding/current
scope/facts/init-name machinery remains shared. `_rewrite` owns the enclosing
transaction; nested committed try work remains rollbackable by that caller.

The opt-in probe pushes a real local scope before snapshotting. Two parsed
early producer slots show read-your-writes: one declaration, one memo row.
A nested transaction creates a separate base global reference, appends an
initializer and origin, changes the exception flag, and commits. A subsequent
parsed source producer deliberately returns an invalid skeleton. Ordinary
binding raises malformed, a native try/catch catches it, and rollback compares
all scope symbols/bindings/enumerators, base global binding maps, name counters,
adapter contents, next_binding, early/inits/origins rows, scalar origin and
needs_exception. The comparison uses Map.equal for copied maps rather than
mistaking copied Map identity for state inequality. It also checks borrowed
adapter owner identity after rollback and successful commit. The native fixture
continues, builds, and executes after the expected compiler error.

The probe's incidental global/init/origin writes test transaction coverage;
they are not extra supported effect kinds. It does not claim rollback of every
Compiler field, global symbol/tag mutation, arbitrary queue clears, parser token
position, helper external I/O, or macro caches. Queues use append-only length
restoration in this boundary. The snapshot omits diagnostic storage and the
internal slot-call metric deliberately.

## Reproduce

```
X2C_DUAL_EFFECT_PROBE=1 \
X2C_HOME=/Users/gary/.codex/worktrees/agent-dual-transport/x2c \
/tmp/x2c-dual-combined-final build \
  --output /tmp/dual-combined-final-smoke \
  --build-dir /tmp/dual-combined-final-native \
  /Users/gary/.codex/worktrees/agent-dual-transport/x2c/unittest/compiler-fixtures/defer-try-cleanup.x
/tmp/dual-combined-final-smoke
```

The preserved log reports `phase4 effects: early-read-write rollback-all
borrowed-map-commit`, native build success, and runtime output `17 1 1 23`.
Unset X2C_DUAL_EFFECT_PROBE for corpus/timing. Full62 comparison and paired
measurements are separate parent/transport evidence and must use this same
saved binary and common X2C_HOME/absolute source inputs.

## Failed attempts preserved

The first build used a Statement meta call without the existing sequence
suffix, producing expected-semicolon and cascading owner diagnostics. Adding
`...` and preserving carrier results before legacy List splicing repaired it.
Probe catch-filter forms were corrected to existing grammar. An invalid probe
field `c.current` was corrected to c.token. The first rollback comparison
incorrectly compared embedded copied Map identities; the failure log is kept,
and the final structural-state comparator passes. These failures concern those
implementations and are not evidence against the combined architecture.

## Read-only cross-review limits

The positive early-effect probe verifies the actual queued declaration and
memo write, then removes that successful test row before fixture emission.
It does not separately compile the static early declaration as emitted C.
The corpus verifies real frame declaration and cleanup emission, where the
parsed body has exactly two producer calls per try; no per-try metric-delta
assertion was added to the final binary. Dispatch increments the internal
metric, but only the actual parsed call path and native results establish
those calls in this evidence.

The narrowed client still uses private explicit stage wrappers. Removing
those wrappers from public-looking lowering code requires the agreed common
application/producer boundary contract; this prototype does not settle that
API. Native dispatch, carrier tags, and early-effect token/memo details are
scaffolding. Full helper ABI and generic user-defined effect producer
execution remain unimplemented.
