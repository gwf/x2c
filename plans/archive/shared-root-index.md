# Shared-root canonical index

> Status: done
> Published to `dev` on 2026-10-29 through PR #628 (merge `a8c3bd36f`).
> Implemented and focused checks passed on 2026-10-29. The matched Notes
> benchmark is recorded under
> examples/apps/notes/bench/reports/2026-10-29-root-index.

The process root keeps an append-only linear-probe index. Writers retain the
recursive root mutex and publish a value before its nonzero hash with release
ordering. String and List readers acquire the published table and hashes
without locking. Other query kinds retain serialized custom equality.

Growth builds a complete replacement using stored hashes and values in a
staging Scope. Failure destroys that Scope; success transfers it to the root
before publishing the replacement. Previous tables and backing Blocks remain owned by the root
Scope until quiescent shutdown. Geometric growth retains fewer old buckets
than the current table contains, plus the old table/Scope/Block records. Private
Pools keep their existing Robin Hood tables and locking. Public layouts and
function signatures stay unchanged, as do later promotions and identity.

Root writes pass through insert, intern and promotion. String construction
must consume the returned canonical identity after a competing insertion.
Reentrant custom equality can grow the root; an absent insertion retries if
its captured table was replaced. Growth copies entries without callbacks.

Verify concurrent native reads, inserts and promotions across repeated growth;
identity and old-value retention; custom callback errors/reentrancy; existing
private Pool behavior; and the Notes APIs. Review the authored diff before
submission, run focused checks and author stage-2, and compare the same
64-client lookup workload against the preserved post-HTTP-change runtime.
Retain all timing samples with the existing host-load caveat.

Design review: the table is the single root index, not a second mirror of a
mutable table. Existing Scope ownership retains old versions; no reader
registration, per-read write, or reclamation thread is added. Retaining
custom callback serialization avoids a new caller thread-safety obligation.
The expected cost is retained index memory and linear probing for root
writes; the measured target is shared-root lookup synchronization.
