# Split large grouped Map hash storage

> Status: done - 2026-11-01.
> Implemented at `0fce29c16`; regenerated bootstrap at `81c08489f`.
> The completed tree passes the publication gate.

## Result

Implement the successful prototype once in the shared grouped generator.
Var Map and Pool keep combined controls/full hashes below 65536 buckets.
Larger tables put an aligned full-hash pointer after the controls and allocate
the hashes in the controls Block's existing lifetime Scope. Cache the hash
pointer per probe and rebuild. Preserve native typed layouts, prefetch policy,
public signatures and structs, key callbacks, and root atomic publication.

Block cleanup, owner moves and Context export already carry Block.lifetime.
Rebuild must transfer that lifetime before moving staged Block allocations.
Guard controls construction so allocation failures reclaim staged storage.
The accepted tradeoff is an internal storage Scope for large tables and the
prototype's roughly 4% large-hit-lookup cost, with headline CPU flat and peak
RSS substantially lower. Keep the prior experiment archive as dated evidence.

## Delivery

1. Port storage allocation and pointer caching. Cover the split threshold,
   foreign allocation regions, Context export and concurrent root growth with
   focused native/scalar/sanitizer checks. Regenerate affected fixture symbols
   and API documentation through existing targets.
2. Review authored changes. Freeze the candidate and compare the same integer,
   direct-operation, word-count and representative compiler workloads against
   the retained current grouped control with matching optimization settings.
3. Integrate current dev, run the existing publication gate, review generated
   artifacts, publish to dev and archive the completed plan with measurements.

## Design review

Reuse Block.lifetime rather than adding a third independently managed Block or
new Context obligations. Keep one probing implementation and one threshold
policy for side hashes. Native typed families compile away the side-hash path.
No new allocator, global synchronization, recurring check or backend selector.

## Delivered evidence

- Var Map, typed Maps and ordinary PoolTable still use one grouped generator.
  Large side-hash caches now use Block-owned storage; native records, public
  signatures, lazy Map content ownership and root atomics remain unchanged.
- Native, scalar, ASan/UBSan and Rosetta x86-64 focused checks each pass 206
  tests and 15,685 assertions, plus a two-million-operation dictionary oracle.
  Tests cover threshold growth under a foreign Scope, direct owner moves after
  growth, source Context destruction and concurrent root growth.
- The existing `agent-pr-check` passes: 1,164 tests, 103,725 assertions,
  1,380 compiler fixtures and 138 matching book outputs, command checks and
  bootstrap/stage comparisons. Generated changes received source review.
- The paired adoption campaign verifies 114 samples plus 28 targeted
  confirmations. Var counting adjusted RSS falls 1406.6 to 1082.0 MB;
  mixed falls 714.5 to 579.6 MB. CPU stays close to current grouped storage.
  Typed mixed confirmation is 2.6% slower and representative compiler CPU
  about 1% higher; the report retains those costs and timing limits.
- Both compiler variants generate fourteen byte-identical files. All four
  measured generated runtime C files also match the final gated files exactly.
- See the [adoption report](../../unittest/benchmarks/hash-table/results/grouped-split-adoption-20261101.md).
  Local raw sources, binaries, samples and gate logs remain under the ignored
  `debug/grouped-split-adoption/`. Full external cohorts, PLSO, Notes and
  build-cost/c2x2c scaling were not rerun for this allocation-policy change.
