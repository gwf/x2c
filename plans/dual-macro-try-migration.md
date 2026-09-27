> Status: active -- scoped production migration, awaiting core support.
> The isolated try proof passes raw C/H parity and rollback. No production
> implementation is authorized by this research plan alone. Implement fresh
> on current dev after the core client contract is delivered and bootstrapped.

# Migrate try lowering to one dual-purpose Macro

Replace the hand-built outer try shape with the same Macro application
contract used for construction and recognition. Retain ordinary region,
binding, typing, cleanup and emission owners. This is the first lowering
migration after core support, independent of capture-role consolidation.

The authoritative contract is
[compiler-dual-macro-contract.md](compiler-dual-macro-contract.md). Evidence:
[phase3](../.context/dual-macro-phase3/),
[phase4 combined proof](../.context/dual-macro-phase4/combined/README.md), and
[phase5 open-body proof](../.context/dual-macro-phase5/README.md). Phase4 tracks
full copies of five compiler sources; its later incremental patches are
research dependencies, not production patches. **Never merge the research
branch into dev.** Author the actual change against current dev.

## Settled shape and client

```x2c
macro open Statement $compiler_try_shape(Name $frame, Statement $declarations,
    Statement $body, Statement $landing, Statement $cleanup) {
  {
    $frame_declaration($frame)...
    $declarations
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else { x2c_exception_landed(&$frame); $landing }
    $place_cleanup($cleanup)...
  }
}

Macro shape = $compiler_try_shape;
return c.bind_syntax(shape(frame_code, declarations, body, landing,
  cleanup_code), AST_BLOCK, c.return_type);
```

The two producer names above express their roles; production uses the ordinary
registered meta-function identities established by core support. They are not
new keywords or globally exposed compiler APIs. `frame_code` and `cleanup_code`
are already completed producer results, not wrapper calls in the client.
Clients do not inspect descriptors, capture rows or stage fields.

Open free program references are prepared once per target Compiler while the
enclosing construct is parsed or bound and scopes are live. Prepare for literal
and canonical try/defer, and managed-cleanup declarations that synthesize tries.
Pass the prepared projections through private bound holes in the common
application machinery. Meta producer names remain closed at definition sites;
default user macros retain closed resolution.

The three header-owned callees preserve existing native String-call projection
and known native result types: void for push/landed, int for sigsetjmp. Ordinary
`Sym.resolve_global` lookup does not create missing semantic signatures or
forward declarations for these functions. Existing generation still places
exception.h through `_primary_include` when `needs_exception` is set. Do not
move includes or publish guessed source declarations. Caller-local helper
shadowing remains baseline behavior and a separate follow-up.

## Producing operations and transaction

| Producer boundary | Stage and established fact |
| --- | --- |
| Ordinary parser or unmarked canonical List | source; ordinary binder resolves and types it |
| Frame new-name consumer | bound typed native frame reference using its allocated binding |
| Catch declaration assembly | lowered sequence after existing declaration/preparation assembly |
| Region body driver | lowered after `_inside` completes exit rewriting |
| Landing assembly | lowered after existing catch selection and unhandled cleanup assembly |
| Cleanup computation | lowered sequence after existing placement and exit computation |
| Frame declaration slot | lowered declaration using the same frame binding |
| Cleanup slot | lowered placement plus cleanup effect |
| Macro application skeleton | source, bound by ordinary `Compiler.bind_syntax` |

Marks attach at these actual exits; they are never inferred from a List head.
Keep raw internal outputs where unwind and other ordinary region consumers
need them. Bound/lowered hole contents stop further binding; the ordinary
parent binder still owns expected types and conversions. The proof's typed
frame exercises declaration, reference, address and member relationships;
this migration does not promise all general Name projections.

Use new-name, early and cleanup effects only. Actual try uses new-name and
cleanup; early is demonstrated by the dedicated success/rollback probe.
Consume them through the extended
existing SymTxn; include early_decls, names.adapters, needs_exception and origin
in rollback alongside existing binding maps, counters and initializer state.
Queues are append-only in the proved boundary; map values are not mutated
in place. Do not generalize that proof to arbitrary state mutation. Producer
implementations and extra effect records are added only when a migration
needs them. Preserve ordinary add_early, adapter memoization and type dispatch;
the template describes shape, not a second semantic owner.

## Implementation and delivery

1. Deliver common core support with the old try lowering still in place.
   The checked-in compiler must consume that source; refresh bootstrap through
   the existing ordinary publication sequence. Only then introduce source
   that uses first-class Macro values, open definitions and slot carriers.
2. In src/transform.x, extract completed producer boundaries from the current
   lowering, preserving allocation order and raw internal region interfaces.
   Reuse `_try_cleanup`, `_inside`, catch preparation and existing Match/List
   operations. Replace only the outer try list build with the template above.
3. Remove obsolete direct construction of push, sigsetjmp and landed calls
   for this outer shape. Keep helpers still needed by declarations, landing,
   cleanup and other lowerings. No prototype-name dispatch, environment probe
   switch, diagnostic instrumentation or test wrapper enters production.
4. Compare all 62 research corpus outcomes and raw generated C/H against a
   current-dev baseline with the same absolute source paths and home. Include
   the existing failing-skeleton rollback probe under core-support checks.
   Record newly encountered incompatibility explicitly rather than normalizing
   generated output to conceal it.
5. Review and fix the authored diff, then use the existing ordinary gate and
   its self-host C comparison. Inspect generated deltas. Deliver on dev under
   ordinary rules; do not add another gate or bootstrap sequence.

## Cost

Phase5 measured +1.40% default and +1.94% live on seven compiler translations;
exception-heavy translation measured +1.37% default and +3.69% live. The
current ledger row replaces phase4 +1.34%, rather than adding it. Record both
application and transaction counts: compiler corpus has two try applications
and two try transactions, among 2119 total default / 2124 live transactions;
exception corpus has four try applications/transactions among 265 total.

[Phase6 profile](../.context/dual-macro-phase6/profile/README.md) isolates the
three-try fixture: 2.876 ms snapshot plus application in the middle sample,
0.959 ms per try. Scope-symbol copy is 40.0%, other snapshot 1.8%, Macro_apply
0.1%, invocation rows 9.3%, replacement 3.8%, binding excluding producers 15.9%,
the two producer evaluations 3.1%, and application residual 26.0%. This
partition excludes commit and surrounding region/preparation work.

Target: preserve or improve the measured phase5 totals and reduce the dominant
snapshot cost through lazy first-write staging in the existing transaction
owner, if implemented in core support. This is an optimization proposal, not
an achieved saving. Retain exact rollback, nested transactions and borrowed Map
identity; never remove coverage to meet the target. The benchmark contains only
two try applications, whose measured work is far smaller than its 85 ms paired
increase. Other ordinary transactions and fixed costs are unclassified.

Recommend a 5% cumulative planning aim for the first three lowerings; 2% remains
an aspiration whose feasibility is unproved. Record the actual combined total
and incremental cost in the research contract's ledger using paired original
baseline runs. This recommendation adds no gate or recurring process.

## Limits

The isolated proof is not a whole self-host validation or a generic helper
transport implementation. General open preparation, mixed Name projections,
parent conversion contexts, precise diagnostics and arbitrary mutable map-value
rollback remain outside this migration. Preserve those as separate work rather
than expanding the try change. Native-helper shadow hygiene is not required
for parity with existing try lowering.

## Plan review

Producer boundaries establish binding identity and completed lowering; clients
consume those facts without provenance checks or a second validator. The
change deletes the outer manual shape and redundant native call construction,
reuses region walking, Match, ordinary binding and SymTxn, and needs only the
common carrier boundary already required by the core contract. Ordinary x2c
code expresses the body and side effects remain ordinary compiler operations.
No new semantic validator, dedicated diagnostic or negative fixture is
proposed. Existing rollback and native-shadow cases protect state restoration
and preserve deliberate baseline behavior through the existing checks.
