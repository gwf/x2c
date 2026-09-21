# Sustained session experiment

This records the first retention fix. See the [long-session assessment](long-session.md)
for subsequent fixes, larger workloads, and current integration limits.

The largest measured retention cost was the outer semantic transaction's map
copies. Reclaiming those copies reduced peak resident storage substantially.
The session still grows with repeated input; parser and Lisp storage remains
session-owned.

## Results

Each row runs in a fresh process and checks the final value or error result.
Before measurements use the session from local commit `96a41c50`; after
measurements use the transient-transaction change. All runs completed after
the measurement client's final-result construction was corrected.

| Workload, 1,000 inputs | Before peak MiB | After peak MiB | Retained allocations per input, before / after |
| --- | ---: | ---: | ---: |
| Update one integer | 155.5 | 62.2 | 135 / 104 |
| Add initialized values | 232.3 | 62.7 | 87 / 56 |
| Add functions | 234.5 | 66.3 | 123 / 92 |
| Reject malformed declaration | 136.9 | 62.3 | 51 / 20 |
| Incomplete parameter list | 158.2 | 57.4 | 74 / 43 |
| Evaluate an expression | 143.9 | 62.2 | 136 / 105 |
| Begin and roll back a transaction only | 142.7 | 61.2 | 31 / 0 |
| Call an existing Lisp function only | 62.0 | 60.0 | approximately 0 / 0 |

This isolates the large allocation cost from evaluator execution: transaction
copies retain storage without parsing or execution, while repeated calls to
one already-defined Lisp function remain nearly flat.

The latest five-thousand-input run after the change:

| Workload | Seconds | Peak MiB | Additional live allocations |
| --- | ---: | ---: | ---: |
| Update one integer | 0.753 | 84.5 | 520,012 |
| Add initialized values | 3.648 | 100.0 | 280,000 |
| Add functions | 3.671 | 105.3 | 460,003 |
| Malformed declaration | 0.712 | 60.9 | 100,000 |
| Incomplete input | 0.626 | 65.0 | 215,000 |
| Expression evaluation | 0.772 | 84.7 | 525,021 |
| Transaction only | 0.550 | 59.4 | 0 |
| Existing Lisp function | 0.020 | 58.8 | 2 |

Measurements are exploratory on this macOS host. Peak RSS includes frontend
startup and allocator caching; it is not the live-byte size of the session.
It varies between processes, so the tables do not imply small RSS differences
are meaningful. Scope live-allocation counts measure outstanding allocation
objects, not bytes. Pool active bytes cover all active pools, while the
interned-value count refers to the current pool. Requested bytes are cumulative
allocation traffic and must not be read as retained storage.

## Ownership change

`ReplSession.submit` opens a detached Scope only while constructing its outer
semantic transaction. Tokenization, parsing, lowering, and evaluation still
allocate in their established session owners. Map backing storage follows its
creation scope when it grows, so the copied containers can be reclaimed with
the transaction Scope.

`SymTxn.commit_transient` commits an active transaction and returns statics,
binding facts, and generated-name counters to their original map owners.
It copies deletions as well as insertions. The existing scope-map commit
already retains original map identities. Rollback restores originals as usual;
the Scope is destroyed only after the last access to the transaction.

This mode requires source-fact collection to be disabled. Source metadata can
retain a staged symbol-map identity, which would dangle after reclamation.
`ReplSession.new` rejects that configuration. Syntax and captured values are
not freed or copied by this change. The ordinary transaction API remains
unchanged for other compiler callers.

The direct API checks include removing a file-static designation inside a
transient transaction and then using the original map after destruction.
Failed initialization, binding-ID reuse, malformed input, and repeated session
teardown also continue to pass. `make verify-fixtures` passes all 747 fixtures
and 1,746 expected artifacts; no expectations were rewritten.

## Reproduce

With the current stage 0 compiler built as described in README.md:

```sh
python3 tools/repl-spike/retention.py 5000
```

The optional driver builds the measurement client and runs all eight workloads.
CSV samples, stderr, and build output go under `debug/repl-retention/`.
The client samples every hundred inputs and checks the final session result.
A process stops if peak RSS exceeds 512 MiB, and the driver reports failure;
an interrupted run is never counted as passing. The measurements add no
repository gate.

The original before/after samples are also retained locally as
`debug/repl-retention-*-before.csv` and `debug/repl-retention-*-after.csv`.
The baseline transaction-only mode used ordinary begin/rollback; its after
mode uses the same short-lived construction Scope as the updated session.

## Remaining work

The fixed-state workload still retains about 104 small allocations per input
and accumulates canonical values. Nested compiler transactions, token storage,
parser scopes, and temporary Lisp function objects remain possible contributors.
This experiment isolates the outer copies; it does not apportion every
remaining allocation. The next ownership investigation should separate those
remaining producers before changing their lifetime.

Growing definitions also still require cumulative map copying, which appears
in their longer run times. The current result improves retention without
introducing another evaluator, replay, a cache, or a general collector.
Comptime coverage work remains separate; its task was still active when this
experiment finished, so no provisional changes from it were integrated.
