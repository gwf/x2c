# Temporary-result ownership

> Status: done - investigation completed 2026-09-12; retain current semantics.
> Delivery commit subject: `overlap native fingerprints and close research probes`.
> No freshness annotation, return inference, or lifetime policy was introduced.

## Result

The guard in `Compiler.discard_helper` is necessary. An ordinary call may
return its temporary input or a view containing it. Removing the guard frees
storage still needed by the result. Current freshness facts safely cover
operator and numeric-converter results; they do not establish ownership of
arbitrary method results. The existing explicit-free and Scope patterns
remain the recommended tools for named loop values.

## Current evidence

The existing `protocol-operator-discard` compiler fixture passed at 2befcb4:

```sh
./unittest/compiler-fixtures/run.sh check --fixture protocol-operator-discard
```

Its expected runtime output was reproduced, including `live 12 discards 9`,
`borrowed 6 named-discarded 0`, `deep 20 discards 2`, and `alias 6 view 6`.
These cover fresh intermediate release, preserved named handles, a function
returning its input, and an aggregate holding a borrowed handle. The fixture
also contains an ordinary `Cell.twice` method that returns a fresh value;
its temporary input is conservatively retained despite that implementation.

`src/expressions.x` records callee identity for protocol operators and numeric
converters. `src/protocol.x` checks that identity before discarding inputs of
pointer/aggregate-returning calls, and carries the same fact through generated
wrappers. The documented contract is in `docs/src/guide/protocols.md` under
operator-temporary cleanup.

The Torch surface contains both apparently fresh wrappers (`Tensor.tanh`,
`Tensor.clone`) and mutating methods returning their receiver (`Tensor.add_`).
A Tensor return type alone therefore cannot authorize input disposal. The
native tensor/storage distinction also matters: a new native handle may share
underlying tensor storage, so wrapper freshness must be traced at the shim.

The existing `packages/torch/benchmarks/REMEDIES.md` already compares explicit
release of replaced named tensors with a Scope per iteration. Those are
historical measurements, not new timings from this investigation. They are
independent of the ordinary-call guard: a named variable's assignment lifetime
is not an unnamed operator intermediate's consumption lifetime.

## Decision and reopening boundary

Do not remove or broaden the guard based on the current evidence. A general
fresh-result annotation would add a caller-visible ownership contract;
body-based inference would add interprocedural machinery and compatibility
questions. Neither is needed to preserve correctness or use existing remedies.

Reopen only with a representative workload where ordinary fresh-returning
methods retain enough temporary storage to justify a narrow proof or explicit
contract. Compare that benefit with existing explicit release/Scope code.
Any design must preserve returned-input and interior-view cases, named aliases,
callee identity through wrappers, and the existing no-discard behavior for
ordinary methods whose results borrow. Do not infer freshness from method
names or return types. No new gate or mandatory fixture follows from this
investigation.

## Plan review

Existing callee facts, Scope ownership, and the current cleanup fixture own
the required guarantees. No representation, walker, cache, validator, or
new diagnostic is introduced. Keeping the guard avoids an unsafe deletion;
keeping ordinary ownership explicit avoids an unmeasured language extension.
