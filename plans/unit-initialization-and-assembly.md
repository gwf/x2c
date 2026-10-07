# Unit initialization, entry setup, and assembly

> Status: active
> The implementation in steps 3 to 6 was delivered to `dev` on 2026-10-07
> from base `48715bde`; see the delivery record at the end. Only the
> deferred memoization section remains, and it waits for named evidence.
> Formerly `deferred-code-and-memoization.md`.

## Goal

The compiler writes code for later insertion: generated declarations,
storage, helper functions, file initialization, function-entry setup, and
the `main` prefix. Give that code one model. A small fixed set of semantic
destinations replaces incidental early/late conventions. One contribution
record replaces the per-producer containers. Assembly consumes the
destinations directly. The result must be shorter, clearer, and no slower.
Generated programs keep their behavior.

Most of this code is initialization. Gary's model is the counterpart of
`defer`. Defer consolidated easily because its meaning is exact: clean up
this before leaving this block. Initialization needs the same clarity: a few
kinds, such as file initialization, function or block entry, cache
registries, and the declaration point. Each kind maps to a fixed area of one
template that every generated x2c source file follows. Gary originally used
the "early" and "late" queues to separate locations, such as exported
prototypes versus statics. The template replaces those conventions with
named areas.

Gary's analogy is a Lisp environment: one model with scoped frames, not a
separate stack for each category of value. Pending code should likewise have
one bookkeeping owner with the scopes it actually needs. Gary suggested one
place for all deferred code without mandating it. This plan adopts one owner
per compiler as the target. It keeps a separate owner only where a lifetime
differs, such as inline bodies shared among related compilers or collected
interfaces that outlive a unit.

Two features serve as design checks. Neither is part of this work.

- **Debuggable decorator.** Register parameters at function entry and locals
  at their declaration points, keep per-invocation frames, and unregister
  through `defer`. It must need no new scope walker or cleanup path.
- **Ordinary `switch` over string literals (not `match`).** A module would
  consume a bound `switch` and contribute selector setup, rewritten case
  discriminants, and optional helpers or cache entries, keeping a real C
  `switch` and its body. It must evaluate the selector once and keep the
  temporary valid for every case. It must preserve adjacent labels, default
  placement, fallthrough, user labels, and nested switches, and rewrite only
  cases owned by its switch. `break` and an enclosing loop's `continue` keep
  their meaning; `Walk._rewrite_switch` in [cleanup.x](../src/cleanup.x)
  already bounds `break` at the switch. Added cleanup
  regions can change which inward jumps are legal, so temporary placement is
  a semantic choice. String equality is a separate decision: pointer
  identity is content equality only within one pool chain, and the empty
  `String` is null. Ordinary `switch` currently passes through to C
  (`statements.x`, `emit.x`); no string-switch lowering or fixture exists.

## Current initialization model

Line numbers are locators at `e18ce3de`; function names are primary.

| Generated code | Builder | Guard | Behavior |
| --- | --- | --- | --- |
| Protocol initializer | `_protocol_initializer`, [generate.x:1024](../src/generate.x) | `_x2c_protocol_guard_` | Wraps the authored `x2c_initialize_protocols` ([common.x:837](../lib/common.x)) with the `<protocol>` statements. The header cache initializer and the synthetic constructor call it first. |
| Header cache initializer | `HeaderCache`, `_header_initializer`, [cache.x:447](../src/cache.x) | `_x2c_hcache_guard_<hash>` | Constructor. Header slots, guard, and batch helpers form a header prelude. `HeaderCache.entries` patches each header function that reads a header cache. |
| File initializer | `_file_init`, `Init`, [generate.x:851](../src/generate.x) | `_init_guard_` | The synthetic constructor `_file_init_`, or the authored type initializer `init_fn`. Runs entry, run-once guard, `<early>`, `<mid>`, authored body, `<late>`, then the `fini_fn` shutdown registration. `Init.patch` patches public entries; a cache-only file patches only entries that reach a cache (`_cache_reachable`). |
| Program entry | `_patch_main`, [generate.x:1506](../src/generate.x) | none | Prefixes `main` with `x2c_initialize()`. |

The three initializers each build a guard declaration
(`initialization_guard`), a run-once test (`_run_once`), and a statement
list. Function entries are patched in three separate passes:
`HeaderCache.entries`, `Init.patch`, and `_patch_main`.

Four producers create the same obligation, storage plus initialization, by
different paths:

| Producer | Storage | Initialization |
| --- | --- | --- |
| Protocol method tables, [protocol.x:2643](../src/protocol.x) | `add_early` | `add_init(<protocol>)` or `add_init(<early>)` |
| Source cache slots, `_source_cache`, [cache.x:552](../src/cache.x) | `_slot_declarations`, `_cache_batches` helpers, `place_source_prelude` | `add_init(<early>)` or `add_init(<late>)` |
| Deferred file statics, `_rewrite_statics`, [cache.x:161](../src/cache.x) | Declaration rewritten in place, then a `sourceinit` helper after it | `StaticQueue` orders them, then `add_init(<mid>)` or `add_init(<late>)` |
| Header cache slots, `HeaderCache.prelude`, [cache.x:458](../src/cache.x) | Header prelude | Its own constructor; never `inits` |

**Placement and execution order are separate axes.** `early_decls` is not
early. `Compiler.transform` ([transform.x:190](../src/transform.x)) drains
it to a fixed point and appends the declarations after the authored unit;
`_forward_declarations` later supplies the prototypes that make them usable.
`<early>`, `<mid>`, and `<late>` order execution inside the file
initializer: literal storage and protocol registration, then file-static
assignments, then work that needs the type initializer's own String or List
canonicalizer. The current names state neither the destination nor the
reason, and the design replaces them.

## Entry-setup inventory

Exit cleanup has one walker (`Walk` in [cleanup.x](../src/cleanup.x)) and one
usual interface (`defer`). `$auto`, `$scope`, `$let`, `$lock`, timing, and
tracing all generate `defer`. Try/finally and static-initialization regions
cooperate with the same walker. Allocator finalizers and shutdown hooks are
runtime registrations.

Entry setup has no such owner. Ten independent paths insert setup ahead of
existing code:

| Scope | Path | Locator |
| --- | --- | --- |
| Block | Decorators prefix statements, paired with `defer` | `_scope_expand`, [builtins.x:31](../src/builtins.x) |
| Function | Mutable-capture parameter cells | `_prepend_setup`, [callables.x:692](../src/callables.x) |
| Function | Exception-preserved parameter escapes | `Preserve.escape_parameters`, [cleanup.x:1215](../src/cleanup.x) |
| Generated function | Callable adapter argument and context setup | [callables.x:192](../src/callables.x) |
| Expression | Ordered-evaluation temporaries | `_ordered_parts`, [transform.x:659](../src/transform.x) |
| Protected block | Exception frames and defer records | `Walk._lower_try`, `Walk._lower_defer`, [cleanup.x:695](../src/cleanup.x) |
| Unit | Generated declarations | `Compiler.add_early`, [compiler.x:2271](../src/compiler.x) |
| File | Generated storage at the prelude boundary | `place_source_prelude`, [generate.x:887](../src/generate.x) |
| File and header | Initializers, constructors, guarded entries | `_file_init`, `HeaderCache` |
| Program | Runtime initialization prefix on `main` | `_patch_main` |

The inventory excludes initialization at a declaration's own execution
point, such as ordinary locals, `$auto`, and lazy local statics. Block entry
is ordinary statement order and needs no new owner. Function entry,
file initialization, and unit support are where the paths multiply.

`_prepend_setup` and `escape_parameters` build the same block prefix.
Parameter cell setup is inserted before normalization; escape setup is
discovered later but currently executes before it. Each caller keeps its
transformation stage. Insertion order alone does not define execution order.

## Other representations and costs

| Representation | Finding | Treatment |
| --- | --- | --- |
| `Compiler.inits` | Each entry carries its phase tag. `init_statements` rescans the whole array for each phase: three times in `Init.statements`, once in `_protocol_initializer`, and three times in `_cache_only`, which discards its lists. | Store by destination |
| Cache `initializers` | `(binding assignment)`, enriched in place to `(binding assignment helper arms)` | One record shape from creation |
| `StaticQueue.pending/state/phases` | Three maps keyed by the same binding; `state` and `phases` can become visiting, finished-ordinary, and finished-late | One scheduling record per binding; account for its allocation |
| `static_init_deps` | Two producers: `_record_static_object` ([compiler.x:1721](../src/compiler.x)) and Func conversion ([transform.x:861](../src/transform.x)) | Keep; it is a dependency fact, not pending code |
| `init_tokens` | Serves the cycle diagnostic and collection | Keep |
| `init_fn`, `fini_fn` | Authored initializer and shutdown names; saved by `SymTxn` | Keep as file-initialization inputs |
| `sourceinit` wrapper | Marks a captured static helper at its source position; read by `_prelude_position`, `HeaderCache.entries`, and `emit.x:331` | Keep the position; decide whether the record replaces the marker |
| `initblock`/`initstmt` | `_file_init` skips them ([generate.x:859](../src/generate.x)); nothing in `src/`, `lib/`, `etc/`, or `unittest/` produces them | Delete the match and its comment |
| `_prelude_position` | Four scans per unit: `_file_init`, `place_source_prelude`, and twice in `_primary_include`. File initialization and the source prelude insert at the same boundary in separate walks. | One boundary per region where ordering permits |
| `declaration_effects` | Deferred Lisp forms with source key, span, syntax, and defining context | Out of scope; compile-time availability is not runtime initialization |
| `pending_inline_bodies` | Shared among related compilers with their provider session | Keep its owner |
| `meta_group` | Tagged rows for meta generation | Out of scope |
| `Walk.regions` | Active cleanup scope used by several exits | Out of scope; not consume-once |
| Literal identities, dependency maps, worklists | Indexes and algorithm state | Out of scope |

**Two rollback paths restore pending code.** `SymTxn` checkpoints
`early_decls` and `inits` only for macro applications
(`transaction.extended`, [symbols.x:1271](../src/symbols.x) and
[1292](../src/symbols.x)). `_speculate`
([initializers.x:734](../src/initializers.x)) separately snapshots and
restores `early_decls`, `id_keys`, `key_ids`, and the adapter map by hand.
The pending owner provides one checkpoint and restore that both use.

## Design

### Destinations

A generated source file has a fixed template with ordered insertion
boundaries, not contiguous buckets. Native directives, `#undef`, conditional
arms, and captured static helpers constrain movement, and the template keeps
that ordered structure.

| Destination | Contract | Replaces |
| --- | --- | --- |
| Public interface | The collector's selection (`FileWalk.select_public`) and existing declaration dependencies | Nothing; unchanged |
| Unit support | Generated types, storage, helpers, and guards. Lowered to completion, placed after source types and before first use. | The `early_decls` tail append, `place_source_prelude`, `Init.prelude` |
| File initialization | Ordered areas around the authored initializer body: protocol setup, literal storage, static assignments, body, post-body work, shutdown | Phase-tagged `inits`, `init_statements` scans |
| Function entry | Setup before an existing body, at a stated transformation stage | `_prepend_setup`, `escape_parameters`, initialized-entry patching, the `main` prefix |
| Declaration point | Work that becomes valid once a binding is initialized | Unchanged; see rejected implementations |

Cache registries keep identity, dependency, and deduplication duties and
supply storage and initialization contributions. Choose names for the file
initialization areas that state their contract. The plan does not fix the
spellings.

### One pending owner

One record per compiler owns pending contributions, with storage per
destination. The destination implies the accepted stage: unit support
accepts unlowered declarations, which the transform drain lowers, and file
initialization accepts lowered statements. Facts already carried by the AST,
such as a binding or origin, are not copied into metadata. Producer identity
is not stored unless a consumer needs it.

The owner provides append, consume-to-fixed-point for unit support, select
by destination, and one checkpoint and restore. `SymTxn` and `_speculate`
both use that checkpoint. An initialization contribution is a storage
declaration plus statements in a file-initialization area. Protocol tables,
cache slots, and deferred statics append through one operation. Header cache
storage remains private to each including C translation unit and stays
header-owned, but uses the same initializer builder.

The first concrete design settles append order, additions made while
draining, release of consumed payloads, and checkpoint validity. A single
mark per destination suffices only while every destination is append-only.
Keep current fixed-point generation.

### Contribution protocol

The macro code-value carrier is the existing contribution protocol.
`_code_effects` ([macros.x:4197](../src/macros.x)) applies ordered effects
under the application's transaction: `new-name`, `cleanup`, and `early`.
The `early` effect already combines a pending declaration with a
once-per-owner memo (`$adapter.memo`). Extend this vocabulary with an
initialization effect instead of inventing a second protocol. Compiler
producers call the same owner operations directly.

### One initializer builder and one entry patch

One operation builds a run-once initializer: guard declaration, run-once
test, statements, and an optional constructor attribute. The protocol,
header cache, and file initializers use it.

One per-function decision replaces the three patch passes. For each
function it selects the protocol initializer, the type initializer, a
guarded public entry, or the `main` runtime prefix. The header region keeps
its own function list and calls the same decision. `_file_init` currently
returns early when a unit has no initialization work. The `main` prefix must
still apply in that case, either through the same visit or in the final
assembly loop.

### Assembly

The pipeline becomes:

```text
select the public projection and preserve ordered source
materialize cache storage and initialization contributions
assemble file initialization and patch entries in one visit
place function bodies and required declarations
assemble final source text
emit
```

Deletion targets:

- Fold `_patch_main` into the entry decision.
- Find the prelude boundary once per region. Insert unit support and the
  file guard in one walk where ordering permits. More than 512 cache
  assignments create batch helpers inside the cache prelude, and the
  current file guard and synthetic initializer land between the slots and
  those helpers. Cache reachability also reads the expanded source. Preserve
  that order explicitly; do not add a virtual source framework to avoid
  materializing it.
- Combine `_primary_include` and source spacing into one final loop.
  Discover both runtime-header anchors in one scan. Preserve banners, guards,
  include order, and whitespace.
- Replace `Partition.source`, which is not the emitted source, with the facts
  its consumers need: whether source content has started and which
  conditional groups hold source content. Keep this only if the replacement
  is simpler.
- Delete the `initblock`/`initstmt` match.
- Delete the manual pending-code rollback in `_speculate`.
- Remove superseded queue fields, APIs, transaction counts, and record
  conversions as clients migrate. A wrapper that keeps the old machinery is
  incomplete.

## Rejected implementations

The planning audit at `0bba0aed` estimated these from source; none was
implemented or measured. Each rejects that implementation, not the
destination model.

- **Shared declaration driver** for managed declarations
  (`finish_managed_declaration`, `parse.x`), lambda-cell declarations
  (`CellRegion._declaration`, `callables.x`), and exception preservation
  (`Preserve._declaration`, `cleanup.x`). About 74 lines would be replaced
  by an estimated 81 to 100. A single after-declaration hook also erases
  their distinct orderings: register cleanup after each initializer, replace
  storage at the declaration, or emit escapes after the whole group.
- **Generic traversal with callbacks.** It needs source-order, postorder,
  inherited-context, and pruning policies, and dynamic callbacks add
  self-translation cost.
- **An `add_early(wrapper_function(...))` helper** over seven sites. It
  saves about two lines.

## Scoped memoization (deferred)

Memoization is not part of the first implementation. It starts only after an
inventory names a repeated substantial computation, with its result,
complete inputs, the point where those inputs become stable, the owner whose
lifetime bounds the result, and its repeated callers.

The contract starts from the existing `$memo` in
[adapter-memo.x](../src/adapter-memo.x):

```text
memo owner + operation identity + complete stable inputs -> reusable result
```

- The owner supplies the validity boundary, using existing Scope and pool
  lifetimes. Do not infer process lifetime from pointer identity or add
  dependency-version graphs.
- Pure result reuse and once-per-owner generation are distinct contracts. A
  hit must not suppress required effects or publish bindings from a
  rolled-back expansion.
- Immutable templates do not imply pure expansion. Fresh names, scope
  resolution, Lisp evaluation, diagnostics, origins, and effects are
  per-occurrence. `freeze_declaration_syntax` and thawing read and install
  semantic facts, so do not memoize them by syntax identity.
- The linked-meta definition digest (`linked_meta_definitions_current`,
  [collect.x](../src/collect.x)) is existing reuse. Definition freshness and
  source freshness stay separate questions.
- Candidate families are prepared decorator and template analysis,
  structural projections, adapter recipes, and analysis against completed
  interface or type information. None is an established miss.

## Existing owners to preserve

- `FileWalk.select_public` selects the public interface; `interface_text`
  serializes it.
- `_replay_cached` and `replay_package_imports` replay ordered declarations,
  includes, and compile-time effects; full parsing installs effects at their
  include positions.
- `_forward_declarations` serves both header and source.
- `Walk` owns region-aware exit rewriting.
- `SymTxn` owns semantic rollback. The pending owner's checkpoint is part of
  it, not a parallel protocol.
- Prepared macro rows, `match-cache.x`, and canonical Lists already reuse
  preparation and structure.

Four recent repairs constrain any reuse of retained syntax:

- `Lisp.bind` moves a retained native stub's `Func` into the session's Scope.
- `_bind_catchcases` resolves a catch pattern before introducing its
  bindings.
- Implementation keyword aliases such as `static keyword loop` stay
  file-local even when their decorator is public.
- Linked-meta reuse keeps provider freshness distinct from definition
  freshness.

## Behavioral invariants

- Cold collection and warm interface replay give the same visible
  contribution. Includes activate compile-time definitions at their source
  points.
- Static definitions, deferred recipes, macro syntax, and provider sessions
  keep their ownership.
- Binding, hygiene, diagnostics, rollback, and per-invocation origins stay
  correct.
- Native directives keep their effects. Public inline bodies keep their
  macro state; ordinary bodies obey `#undef` and conditional arms. Captured
  static helpers stay at their source positions.
- Static initialization keeps dependency-before-consumer order and late
  propagation; independent roots keep source order; cycles keep their
  diagnostic.
- The file initializer keeps entry, guard, protocol, literal storage, static
  assignments, body, post-body work, and shutdown order. The protocol
  initializer still runs before any String- or List-backed cache. Cache-only
  files still patch only reachable entries.
- Entry setup keeps its transformation stage and current execution order.
- Cleanup keeps normal exit, return, break, continue, goto, exception, and
  finally behavior through existing owners.

## Execution sequence

These are checkpoints in one connected change.

1. After execution is requested, fetch `origin/dev`, set up an isolated
   worktree and delivery role under current `AGENTS.md`, and reconcile the
   locators above.
2. Build the compiler and record focused fixture output as the baseline.
3. Introduce the pending owner with unit support and file initialization as
   its first destinations. Move protocol tables, cache slots, and deferred
   statics onto it. Give the cache initializer record one shape. Route
   `SymTxn` and `_speculate` through its checkpoint. Delete the replaced
   fields, APIs, counts, and the `initblock`/`initstmt` match in the same
   change.
4. Build the one initializer builder and the one entry decision. Fold
   `_patch_main` into it.
5. Share the prelude boundary and the final assembly loop. Replace
   `Partition.source` and collapse `StaticQueue` state only where the
   completed replacement is smaller.
6. Share function-entry insertion between `_prepend_setup` and
   `escape_parameters`, and add the initialization effect to the code-value
   carrier if a producer uses it.
7. Review and fix the completed authored diff for duplicated guarantees,
   unnecessary fields, adapters, dispatch, and traversals. Update internal
   documentation through repository targets.
8. Run focused checks, the performance comparison, and the publication
   validation from current `AGENTS.md`. Record revisions, commands, results,
   and remaining limits, then archive or update this plan.

## Validation

Use existing fixtures under
[unittest/compiler-fixtures](../unittest/compiler-fixtures) first; read
[unittest/AGENTS.md](../unittest/AGENTS.md) before running them. Compare
generated C and header output, diagnostics, and runtime results.

| Concern | Starting points |
| --- | --- |
| Cold and warm interfaces | `ordinary-interface-cold`, `ordinary-interface-warm`, `ordinary-interface-unit-order`, `ordinary-interface-unit-order-warm`, `ordinary-interface-meta-order` |
| Private compile-time context | `ordinary-interface-static-macro`, `ordinary-interface-static-keyword`, `ordinary-interface-meta-static-lisp`, `keyword-alias-included`, `keyword-identifier`, `meta-included-file-constants-shadowed` |
| Rollback and identity | `macro-enumerator-rollback`, `macro-type-fields-rollback`, `macro-catch-binders`, local macro and hygiene fixtures |
| Native ordering and captured initialization | `header-promoted-include-macros`, `static-native-source`, `c-macro-redefinition`, `initializer-native-identity` |
| Initialization and dependencies | `conditional-file-init`, `conditional-type-initializer`, `conditional-type-initializer-compiled`, `cache-reachability`, `literal-cache-init`, `private-typedef-order` |
| Lifecycle | Defer, try/finally, scoped allocation, return, break, continue, and goto fixtures selected by changed consumers |

Check existing coverage of cache batching beyond 512 assignments, units
without functions, header caches, and units with `main` but no
initialization work. Add a fixture only for a public invariant that lacks
coverage. If the change touches linked-meta reuse or retained stubs, select
cases from `run-meta-helper.sh`, `run-meta-cache-key.sh`, and
`run-package-install.sh`.

Follow [performance guidance](../agents/performance-checkpoints.md). Compare
converged toolchains with identical inputs, and report elapsed time,
instruction counts, and allocations separately.

## Acceptance

- A net reduction in authored production code, including all new
  infrastructure. Report generated-code changes separately.
- Fewer independent accumulation, rollback, initializer-building, and
  entry-patching paths.
- Preserved fixture output and generated-program behavior.
- No material compiler-performance regression. Fewer traversals is static
  evidence, not a measured speedup.

Narrow or reject a step that adds more representation or dispatch than it
removes. The small size of individual current helpers does not reject the
shared model; test it with the combined clients above.

## Plan review

Collection establishes visibility; replay establishes compile-time
availability; binding and `SymTxn` establish identity and rollback;
`StaticQueue` and cache reachability establish initialization order; `Walk`
establishes cleanup. The design consumes those facts without revalidating
them.

It reuses canonical ASTs, the code-value carrier, `$adapter.memo`,
`_forward_declarations`, `_prepend_setup`, and cleanup. It deletes three
initializer builders, three entry-patch passes, two pending-code rollback
paths, phase rescans, a dead marker, repeated boundary scans, and record
conversions. Each new field or operation must replace one of those.

No new validator, diagnostic, negative fixture, recurring gate, generic
event bus, scheduler, or universal cache is proposed. Memoization waits for
named evidence.

## Delivery record

Delivered 2026-10-07 by one orchestrated batch from base `48715bde`. Four
workers changed disjoint regions; the orchestrator integrated them and
renamed across files.

- **Pending owner.** `Compiler.pending` (`Pending`, compiler.x) replaces
  `early_decls` and `inits`. It holds one array per destination: `<support>`
  and the file-initialization areas `<protocol>`, `<prepare>`, `<statics>`,
  and `<finish>` (formerly `<early>`, `<mid>`, `<late>`). `add_early` is now
  `add_support`. `SymTxn` and `_speculate` share `Pending.checkpoint` and
  `Pending.restore`; a failed speculation now also drops initialization
  statements it queued. The code-value effect keeps its macro-visible
  spelling `early`.
- **Static initializers.** `StaticQueue.record` creates each record as
  `(binding assignment helper arms)`, and one `state` map replaces `state`
  and `phases`.
- **Initializers and entries.** `_run_once` builds the body of all three
  run-once initializers. `Init.enter` is the one entry decision for source
  functions and header cache readers. `_header_initializer`, `Init.patch`,
  `_patch_initialized_entry`, and the `initblock`/`initstmt` match are
  deleted.
- **Assembly.** `_anchors` finds both boundaries in one scan, and
  `_source_text` replaces `_primary_include`, source spacing, and
  `_patch_main`. `Partition.source` is replaced by `source_started` and
  `source_groups`.
- **Function entry.** `Compiler.prepend_setup` serves parameter cells,
  parameter escapes, and callable adapters.

Narrower than designed:

- The `main` prefix is applied in `_source_text`, not in `Init.enter`.
  Applied earlier, `_forward_declarations` emits an extra `x2c_initialize`
  prototype into `main.c`.
- The source region still finds its prelude boundary twice: once in
  `_source_cache` for cache storage and once in `_file_init` on the expanded
  source. Sharing it needs a channel between the two stages.
- No initialization effect was added to the code-value carrier, because no
  producer needs one yet.

Evidence: the compiler built before the change and the compiler built after
it translate the changed `src/*.x` and `lib/*.x` to byte-identical `.c` and
`.h` files. Authored source, probe, and command changes total 394 insertions
and 439 deletions. Workers ran the focused fixtures named above; a fixture's
`.ast` or `.transform` origin numbers shift whenever `src/` differs from
`bootstrap/`, and the publication gate's bootstrap refresh removes that
effect.
