# Retire Robin Hood Map storage

> Status: active - 2026-10-31.
> Gary authorized adoption after the grouped Var sanity check. This replaces
> the remaining runtime Robin Hood families, not the external benchmark tables.

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
