> Status: done
> Sustained session measurements and bounded transaction reclamation completed
> locally on 2026-09-20. No push or production integration authorized.

# Reclaim REPL transaction copies

Compare fixed state updates, increasing values/functions, failed/incomplete
input, transaction construction alone, and repeated evaluation of an installed
Lisp function. Keep the execution subset and redefinition policy unchanged.

Measurements isolate outer transaction map copies as the dominant retained
byte cost. Give transaction construction a detached Scope, then return to the
session Scope before parsing or evaluation. Rollback restores original maps;
transient commit copies all staged contents back to original owners, including
removals. Destroy the temporary Scope after the last transaction access.
Source-fact collection is incompatible because it retains copied map identity;
the REPL rejects that configuration.

The change does not reclaim syntax, canonical values, evaluated objects, or
nested transaction copies. Their existing ownership remains in effect.
The other comptime task was active, so this iteration does not integrate its
provisional work or expand execution coverage.

Validation: eight workloads complete 5,000 submissions each and verify final
state. Transaction-only additional live allocations fall from 31 per input to
zero. At 1,000 inputs, fixed-update peak RSS falls from 155.5 to 62.2 MiB;
retention remains nonzero outside the reclaimed transaction copies. Direct
API tests verify map identity and deletion handling after destruction, plus
existing recovery, initializer failure and session teardown. Eighteen terminal
checks, native parity, and all 747 compiler fixtures pass.

## Plan review

Maps borrow their entry values and own their backing arrays in their creation
Scope. Only transaction construction runs in the new Scope; later code and
values retain their established owners. The new commit method reuses ordinary
scope-map commit and restores the three remaining map identities. Deletion
handling preserves observed file-static removal semantics. The source-facts
restriction prevents a proven dangling-map-identity risk. There is no new
value representation, evaluator, persistent cache, or recursive ownership
validator. A direct deletion/identity check protects the new lifetime boundary.
The optional measurement driver creates no recurring validation requirement.
