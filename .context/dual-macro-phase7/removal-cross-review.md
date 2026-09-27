# Selective construction cost removal: independent read-only review

Reviewed the isolated source and `selective-cost-removal.patch`, then the saved
candidate counts, rollback log, patch/base verification and 62-case comparison.
No build, probe or timing run was performed by this reviewer. The uninstrumented
candidate is `/tmp/x2c-dual-phase7-final`, SHA256
`6cd4db4a97be7918a2291cbe8fcfb2c3f0422a5fde43864337dc7e487f9c181b`.

## Passed

The transaction stores `extended` at entry. Added adapter/base-binding map
staging, queue/scalar snapshots, commit merges and rollback restoration all
use that stored flag. Ordinary transactions retain their original snapshot
behavior. The try driver arms its private dynamic context before the outer
transaction and frame issuance, through finalizer/body/catch walks, producer
assembly, shape application, effects and commit/rollback. Nested transactions
inherit coverage. The opt-in rollback probe activates the same context before
its first snapshot and outer transaction, including its nested commit and
successful borrowed-map commit control.

The saved rollback run reaches `early-read-write rollback-all
borrowed-map-commit`, builds successfully and executes with `17 1 1 23`.
The saved comparison reports the same source root, 62 cases and no changed
cases: outcomes and raw generated C/H remain at baseline parity. Root's reverse
patch check confirms all four changed sources return to verified phase5 base
hashes. These support the scoped removal, not just an alternative explanation
of its cost.

Summing the saved instrumented count rows for the seven compiler/tokenizer
sources gives 2,119 ordinary transaction entries in default mode and 2,124 in
live mode. Only two entries have extended coverage in either mode, matching
two template applications. The exception benchmark separately has 265 total
transactions, four extended transactions and four applications in each mode.
This confirms the selective rule removes additional map copies from ordinary
entries; it does not remove their established baseline snapshots. The counts
come from the separate count binary, not instrumentation in the timed final
candidate.

Carrier recognition is likewise scoped to application binding. Plain ordinary
expression/node binding does not inspect the new stage carrier shapes. The
old dormant retained-hole Map branch remains in the isolated prototype; it
is not used by the try path and the production plan deletes it. The frozen
client gains no public stage wrappers.

## Failures and preserved baseline limitations

No new failure appears in the saved narrowed proof. Existing baseline native
helper shadowing remains a separate follow-up. Baseline macro expansion already
records origins inside ordinary transactions, and initializer conversion has
its own adapter/early-declaration rollback handling. This removal deliberately
preserves ordinary transaction behavior; it does not claim to close every
pre-existing rollback gap.

## Thin evidence and production boundary

The prototype establishes context ownership for the migrated try driver and
its nested operations. It does not prove automatic context entry for every
standalone public Macro application. The core plan explicitly assigns that
entry to the common first-class application owner and forbids activating every
legacy `_invoke_definition`; doing so would restore the unnecessary copying.

Direct legacy invocations returning new effect-bearing slot carriers need
entry into the same construction driver before argument/effect preparation.
That compatibility edge remains unproved. A nested first-class application
must not commit effects that survive a later rollback of an unextended legacy
outer transaction. Neither broad eager coverage nor a carrier check added to
every ordinary binder is justified by the try evidence.

Current open preparation contains fixed native emission facts with audit-only
resolved bindings. General open references prepared from provisional
speculative declarations require explicit cache transaction ownership; the
current proof does not establish it. Append-only queues and immutable staged
map rows remain the transaction boundary. Arbitrary in-place row mutation and
destructive queue edits are not covered.

Timing is independent evidence still being collected; no throughput claim is
inferred from operation counts or this review.
