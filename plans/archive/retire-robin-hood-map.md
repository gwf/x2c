# Retire Robin Hood Map storage

> Status: done - 2026-10-31. Superseded for tables of 65536 buckets or
> more by [split storage](grouped-map-split-storage.md) on 2026-11-01.
> Implemented through `027c1f2b253c2ea5ad5c4c090b432e7dcc56282e`;
> the final publication gate passes. Var Map, typed Maps and ordinary PoolTable
> share grouped storage. Runtime Robin Hood storage is removed.

## Result

Use one grouped storage generator for Var Map, typed Maps and ordinary
PoolTable. Delete the Robin Hood generator and duplicate typed update family.
Keep public signatures, container layouts, Scope ownership, borrowed values,
custom hash/equality behavior and failure guarantees. No runtime selector,
new lock, allocator or caller obligation is introduced.

Var Map and PoolTable retain full hashes beside the controls in the existing
hash Block: padded control bytes, unsigned deleted count, then unsigned hash
per bucket. Records remain two Vars and one Var respectively. Lookups filter
by full hash before custom equality; rebuilds reuse hashes without callbacks.
Typed String/counting families keep their hashes in existing record padding.
Other typed families keep their existing recomputation policy.

The process-root Pool index already uses append-only atomic linear probing,
not Robin Hood. Keep its publication, immutable entries and retained versions;
only locate its existing 32-bit atomic hashes in the shared allocation. Root
readers never inspect concurrently written SIMD controls. Ordinary pool String
lookup uses grouped controls while retaining its allocation-free byte path.
Keep the native SIMD include late/private to avoid public-header compile cost.

## Delivery

1. Preserve baseline artifacts and integrate current dev. Implement shared
   side hashes and Pool ownership policy; migrate Map export, ordinary Pool
   lookup and root hash access. Remove obsolete generators and migrate their
   two compiler fixtures. Update authoritative documentation.
2. Run focused Map/Pool/Context/ownership/thread tests, custom hash/equality
   failure cases, scalar and sanitizer checks. Verify callbacks are not added
   during growth, invalid precomputed hashes remain absent, and tombstone
   cleanup/export preserve values and owners. Review authored/generated diffs.
3. Check paired Var counting/mixed, String word-count time/memory, typed Map
   regressions and compiler/Pool cost before broad publication work. Freeze
   the final candidate, coordinate quiet CPU use, and run the existing final
   publication gate once after focused issues are resolved. Keep performance
   evidence separate; repeat only affected measurements after changes.
4. Publish the validated final tree to dev, update the comparison and report
   exact verification, measured gains, memory costs and remaining limits.

## Plan review

Reuse the existing grouped algorithm, shared operations and ownership helper.
A compile-time side-hash flag and the existing owned/unowned distinction
serve real consumers; neither selects a backend at runtime. All cache writes
occur with record insertion, and occupied controls determine valid entries.
The root's atomic full-hash publication remains its owning concurrency
boundary. Its unused controls cost one byte per bucket, avoiding a second
allocator or a change to root synchronization. Review and measure this cost.
Retain the public failure contracts rather than tests of obsolete displacement
or corrupted Robin Hood arrays. No new recurring validation target is added.

## Delivered evidence

- Runtime changes are in `258290d23` and the staged export correction in
  `8f8e0b74e`. `027c1f2b2` refreshes bootstrap, traversal-order examples,
  three fixture outputs, and the benchmark report. The intervening prefetch
  experiment is reverted; lookup/update/growth code matches the accepted
  measured candidate.
- Native, scalar, ASan/UBSan and Rosetta x86-64 checks each pass 205 tests,
  15,676 assertions and a two-million-operation differential Map check.
- `tools/gate-state.py ensure agent-pr-check` passes on the completed tree:
  1,163 tests, 103,716 assertions, 1,380 compiler fixtures, 138 book outputs,
  command checks, and bootstrap/stage comparisons. Logs are in the ignored
  `debug/retire-robin-hood/publication-gate-final.log` and
  `debug/agent-pr-check/`. Initial gate failures exposed one staged-pointer
  lifetime warning and traversal-order expectations; both are resolved.
- The accepted 114-sample paired campaign verifies every checkpoint and word
  count. Var mixed CPU improves about 25%; counting is roughly flat. The
  representative source-prelude compiler comparison uses about 13% less CPU.
- Var live bucket allocation increases 5%; observed counting peak RSS rises
  about 31% because macOS retains freed growth buffers. No allocator changes
  were added. The memory cost remains documented rather than hidden.
- See the [retirement report](../../unittest/benchmarks/hash-table/results/robin-hood-retirement-20261031.md)
  for absolute time/memory values and scope. PLSO, Notes, Linux/GCC and the full
  external-table cohort were not rerun for this retirement. The prior full
  benchmark campaign remains historical evidence.
