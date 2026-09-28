> Status: done 2026-09-27 -- delivered to `dev`.
> `_rewrite` lowers every try through `$compiler_try_shape`, a
> `macro open Statement` in src/transform.x. The 62-case corpus keeps every
> outcome; C/H differ only by two forward declarations.

# Migrate try lowering to one dual-purpose Macro

Research evidence is retained on `codex/compiler-dual-macro-spike` at
[`1e2d5607`](https://github.com/gwf/x2c/commit/1e2d5607be514c7205507d3f6e39c889e0cff7ec).
Source offsets refer to the research baseline;
verify current owners before implementation. All `.context/` paths below name
repository paths on that pinned research branch, not files delivered to dev.
The research branch contains compiler snapshots and must not be merged.

Replace the hand-built outer try shape with the same Macro application
contract used for construction and recognition. Retain ordinary region,
binding, typing, cleanup and emission owners. This is the first lowering
migration after core support and its bootstrap refresh. Core support follows
capture-role consolidation.

The authoritative contract is
[compiler-dual-macro-contract.md](../compiler-dual-macro-contract.md). Evidence:
[phase3](https://github.com/gwf/x2c/tree/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase3/),
[phase4 combined proof](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase4/combined/README.md), and
[phase5 open-body proof](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase5/README.md). Phase4 tracks
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

Activate the private template-construction context before beginning the outer
transaction and before frame allocation. Retain it through region preparation,
application and transaction completion; nested transactions inherit coverage.
Do not activate extensions on unrelated macro/initializer transactions. Stage
recognition belongs only to the application binding context, entered by the
common owner without a client flag or wrapper. Use core support's distinct
contexts rather than the prototype's shared dispatch/origin flag.

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

The cost target comes from the phase7 selective candidate, not phase5's
unconditional support path. Record its same-window total versus the original
baseline, default and live separately, then derive later migration increments
by subtracting cumulative ratios measured against that same baseline.
The measured reference is phase7: +0.133% default compiler total and -1.318%
live (broad overlapping ranges, no speedup claim); exception is +0.869%
default and +0.122% live. Same-window phase5 control is +1.625% default /
-0.117% live; removal is -1.492 / -1.201 percentage points. Exception default
is +0.506 pp worse than its control. Preserve that result, not just the improved
compiler corpus. See [paired results](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase7/comparison/summary.json).

The first per-lowering row covers this try migration; historical phase5 support
cost is not charged anew to every future lowering.

Application counts remain two per compiler-corpus mode and four per exception
benchmark mode. Total transaction counts remain 2119 default / 2124 live for
the compiler corpus, and 265 for each exception mode; extended coverage is now
only two and four respectively. The 2119 total is across seven translations.

[Post-removal spans](https://github.com/gwf/x2c/blob/1e2d5607be514c7205507d3f6e39c889e0cff7ec/.context/dual-macro-phase7/post-try/README.md) measure
the current candidate: 1.488 ms per try default compiler corpus / 1.818 ms live
(two applications each, one run per mode). The three-try fixture has median
0.922 ms per try, range 0.881--1.073 across three runs. Exception has 0.931 /
0.857 ms per try (four applications each). These windows cover snapshot and
application only; retain their scope-copy child as part of snapshot, not an
extra cost. Commit, frame allocation and region preparation are outside them.
Do not divide the whole compiler delta by two and call it isolated try time.

Cost target: preserve the phase7 whole-candidate result within the existing
advisory checkpoint's ordinary variability, with this measured per-application
work as the first lowering's reference. The old phase5 fixed cost must not
return in core support or be multiplied into later migration estimates.

Keep the 2% cumulative default translation-overhead aim; withdraw the unsupported
5% recommendation. Combined three-lowering feasibility still requires actual
combined measurement. Use the existing advisory checkpoint, with no new gate.

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

## Delivery outcome

The try case in `_rewrite` arms the application context, begins the outer
transaction, and allocates the frame, in that order. Its producing
operations attach stages: the catch declarations and frame declaration
form one lowered sequence, the region body and landing are lowered, and
the frame reference is bound. The template calls
`builtin_try_frame_declaration` and `builtin_try_cleanup_placement` in
its slots; the second returns the placed cleanup with the cleanup effect.
The client reads `shape(frame, declarations, body, landing, cleanup)`.

Decisions made during delivery:

- The producers are compiled into the compiler in src/builtins.x and
  registered in `builtin_targets`, so the template calls them by name in
  any unit it is applied to. A `meta` function in compiler source is not
  reachable there. src/transform.x declares both producers: without the
  declarations, declaration collection fails on the template and drops
  every later declaration of the unit. They receive the carriers the
  lowering computed.
- The frame is an `Expr` hole. The template uses it only as `&$frame` and
  `$frame.env`, and a bound frame reference is an expression.
- The three runtime calls bind through the open rule. `x2c_exception_push`
  and `x2c_exception_landed` bind to the unit's declarations, so generated C
  now forward declares them; `sigsetjmp` stays a native call. That is the
  only C/H difference across the corpus, re-baselined in 25 fixtures.
- The client was reduced on 2026-09-27 to what the contract promises.
  Stages attach where values are produced: `_try_frame` returns the bound
  frame reference, `_try_region` the lowered body, and `_try_cleanup`,
  `_try_declarations` and `_try_landing` lowered sequences; `_inside`
  accepts a lowered cleanup. `bind_syntax` accepts a pending application,
  converts it through `evaluate_macro_slot`, owns its application context
  and transaction through the existing `m-invoke` case, and returns the
  one item of a directly applied value at statement or unit position.
  `Compiler.macro_value_syntax` is deleted.
- The frame stays an ordinary `_region_binding` allocated before the
  application, and the transaction covers only the application. The
  region exit statements `_inside` records while rewriting the body are
  built from the frame binding before the application runs; routing the
  frame through a `new-name` effect would need a second, token-based
  representation in every region consumer.
- The producers stay in src/builtins.x rather than src/linked-meta.x.
  `Compiler.bind_linked_meta` binds a linked copy only when a unit parses
  that `meta` definition through an import; a user unit containing a try
  never parses the compiler's definitions, so a linked producer would be
  unbound there. Builtins are installed in every compile-time session.

Validation: all 62 cases (46 try fixtures and eight corpus files in
default and live) keep their exit status; 18 are byte-identical and 44
differ only by the two forward declarations. The gate's self-host
comparison passed. The rollback check in `commands/repl/tests/api-check.x`
applies a carrier with `new-name`, `early` and `cleanup` effects whose
skeleton fails to bind, and confirms that early declarations, adapters,
generated-name counters and the exception flag are unchanged; it reports
a leak when rollback is disabled. Timing and counts are the production
rows of the contract ledger.

Thin evidence:

- The rollback check drives the carrier path under a recovering compiler
  directly. No user input makes the fixed try shape itself fail to bind.
- Timing is five alternating pairs on one host. The exception workload
  is about 1% slower, above the phase7 reference.
