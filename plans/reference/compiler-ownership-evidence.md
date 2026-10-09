> Status: reference
> Static ownership inventory at 548b381f18653089b0285082881f27d65df3bf94,
> investigated 2026-10-09. No compiler change or runtime defect is asserted.

# Compiler ownership evidence

Companion to the [integrated assessment](../compiler-ownership-investigation.md).
The field groups describe existing operations, not proposed components.

## Complete Compiler field coverage

All 109 declared fields in src/compiler.x:82-219 appear below exactly once.
Groups describe operations and lifetimes; they are not proposed components.
Default allocation lifetime is the active Scope. In the frontend that is the
unit Context. Compiler-local means independent mutable identity, not a separate
allocation arena or immediate destruction at close_child.

| Group | Complete field membership | Ownership and replacement rule |
| --- | --- | --- |
| Current input and source coordinates | filename, text, token, input_boundary, tokenizer, line_markers, directives_taken, arms, arm_stacks, layout_marks, packed_marks, braces, lines_text, line_starts, layout | Tokens borrow tokenizer backing storage; text may borrow request overlay or unit interned text. Arrays/maps are compiler-local. Segment token positions are shifted to whole-file coordinates. Filename changes for include replay and temporary group emission. |
| Configuration borrowed into translation | root_dir, include_dirs, sources, source_map, source_facts, source_primary, unit_script, script | root_dir comes from environment; include_dirs and sources come from request/frontend. SourceView must outlive units. unit_script is a unit-owned shared record; script points to it only for its owning file. source_primary is compiler-local. source_facts is inherited but disabled for CPP and temporary meta emission. |
| Package registration and resolution | package, package_dirs, package_roots, package_aliases, package_members, package_effects | new_shared aliases these values. package is a compiler-local spelling. configure_package copies package_roots when registering a previously absent package for a cold provider; aliases/members/effects remain shared. No uniform permanently-shared package object is currently valid. |
| Translation identity and provenance | names, origins, origin | names points to one GenNames record; next_binding stays unit-wide for live bindings; SymTxn restores it on rollback, so unpublished temporary numbers can be reused. Its counters are temporarily replaced for cold files and copied for macro production. adapters/file_scope_owners are copied during meta emission. origins usually aliases the unit array, but emission copies it; origin is compiler-local. |
| Semantic table and lexical binding context | sym, params, return_type, aggregate_type, fn_name, lambda_scopes, match_types, in_pattern, match_is, in_proto, local_macro_captures, local_macro_capture_scopes | Constructor creates a fresh Sym with a back-pointer; builtin definition child replaces it with owner Sym. params is a by-value SymScope containing shared map handles. Function and binding operations save/restore return_type and params. Scope stacks establish semantic visibility; allocations usually persist until unit teardown. |
| Macro state carried between segments | macros, object_macros, imports, kw_aliases, declaration_effects, evaluated_effects, id_keys, key_ids, macro_lisp, borrowed_lisp, inherited_lisp | take_unit_state shares literal arrays/maps plus segment state. return_unit_state copies replacement handles back and marks the child Lisp borrowed. Cold file ordinarily starts fresh effect evaluation and Lisp; preload borrows shared Lisp. Literal containers remain aliased for segment bodies. Session is an explicit independently allocated resource. |
| Current expansion and parse control | macro_stack, expansion_floor, macro_holes, macro_application, macro_count, builtin_defs, meta_body, meta_statement, open_linkage, recovery_depth, declaration_produced | Mostly lexical/temporary values restored by callers or reset for passes. Some flags are inherited in new_shared. open_linkage passes between segments. declaration_produced propagates explicitly because scalar assignment does not share mutation. |
| Protocol tables and derived answers | protocols, conforms, protocol_helpers, proto_cache, adoptions, import_protocols, collect_protocols | Compiler-local semantic tables rebuilt from visible declarations. proto_cache is discarded when protocol/adoption publication changes answers. protocol_helpers is copied for isolated group emission. import_protocols records lazy registry installation. |
| Translation effects and output staging | deps, included_effects, init_tokens, static_init_deps, fn_defs, init_fn, fini_fn, pending, prelude, runtime_inc, runtime_hdrs, runtime_literals, inline_header, needs_exception | Fresh mutable tables or arrays per Compiler, with explicit child merge of deps/fn_defs. pending contains five independent arrays. Some scalar policy and names are required from the owning compiler for backend emission. Group emission replaces or copies relevant state then restores saved Compiler. |
| Compile-time definitions and staging | meta_comptime, meta_regions, meta_hashes, meta_calls, native_meta, project_meta, unit_nodes, meta_group, meta_group_bound, meta_build | Mostly compiler-local maps and arrays; selected meta_hashes can be process-cache-backed and shared while segments fill them. share_meta_group explicitly aliases group and bound map with the Lisp session. Full parse clears/replaces metadata. meta_build is inherited by related compilers. |
| Collection mode and delayed provider work | shallow, source_private, public_bodies, interface_provider, signature_only, pending_inline_bodies | Modes are compiler-local. pending_inline_bodies aliases one unit queue. public_bodies prevents early Lisp destruction of providers whose inline bodies require later graph completion. Queue retains Compiler pointer and original input/semantic maps. |
| Diagnostics routing | diagnostics, import_stack | New compiler ordinarily gets fresh Diagnostics with inherited limit. borrow_diagnostics aliases a store and changes its printer; caller must restore printer. import_stack is independent array and is cleared at pass starts. free_lisp also clears diagnostics and is terminal cleanup. |
| Unit semantic source records | source_occurrences, source_definitions, source_declarations, source_texts | Created only for source-fact requests, shared into child compilers. Source text values can borrow longer-lived request overlays or unit disk reads. Semantic transactions and child merges affect these stores; they end at unit close. |

Field grouping does not prove that every transient value is restored on every error
path. See the transaction distinctions in the main assessment.

## Ownership table outside Compiler

| Owner | Lifetime | Owned values | Borrowed dependency and ending operation |
| --- | --- | --- | --- |
| Frontend | Request/command Scope | Frontend struct, include search setup, toolchain handle | CliRequest and SourceView; units sequential. src/frontend.x:19-40,536. |
| ParsedUnit | One translation unit or REPL session | Context, compiler and CPP handles, retained outputs/globals/AST | Results borrow Context until close/export. close calls child cleanup, free_lisp, Type.end_unit, Context.close, then zeroes record. src/frontend.x:157-164. |
| Context | Lexically current lifetime | Detached Scope, optional private Pool, Error state, Match state | Parent/destination Scope and Pool borrowed. Close Match/Error before Pool, then Scope. lib/context.x:285-350. |
| Scope | Allocation lifetime | Mutable containers and finalized Compiler allocation | Compiler finalizer releases owned Lisp. Canonical values generally live in Pool rather than container Scope. src/compiler.x:2764-2781,2833. |
| Pool | Canonical identity lifetime | Interned String/List storage | Inner values must promote or export before outer owners retain them. agents/x2c-philosophy.md:674-710. |
| Sym | Compiler/unit allocation lifetime | Scope stack, statics, binding facts, undo storage | Compiler back-pointer, input globals/overlays. Lexical push/pop changes visibility, not necessarily allocation lifetime. src/symbols.x:100-122,193-196. |
| SourceView | Request Context | Overlay and dirty-path maps | Immutable configured text; frontend/compiler borrow view. Disk text is deliberately not cached in view. src/sourceview.x:13-38,52-71. |
| Process collection cache | Process | Scope-backed declaration maps, dependency maps, cache map | Canonical payloads retained via try_own; does not retain Compiler/Lisp/tokenizer pointers. _cache_shutdown destroys scope. src/collect.x:74-148,1035-1062. |
| Interface reader | Process | Lisp reader and source-hash/provider maps in process cache Scope | Hook destroys Lisp separately before cache Scope ends. src/collect.x:1657-1674. |
| Type source-declared tags | Unit, stored in process-global slot | Unit-scope declared_typetags Map | begin_unit replaces global slot; end_unit NULLs before unit release. Units must be sequential. src/type.x:810,883-895; src/frontend.x:169-173. |
| Type scalar facts | Process/static | scalartypes native generated table | Distinct from source-declared unit tags. src/type.x:578. |
| Compiler Lisp | Explicit session lifetime bounded by Compiler cleanup | Detached Lisp session/user Scopes; globals, lambdas, transferred Funcs | Canonical values and pointer payloads may still borrow caller/Pool owners. Adopted frozen library parent must outlive child. lib/lisp.x:1755-1777,1805-1836. |
| Shared macro library | Shared build-target session, with process-hook fallback | library_scope, Lisp and import/definition/comptime maps | Frozen before children adopt; hook or macro_library_reset destroys session before build-target Context ends. src/macros.x:4570-4599,4640-4654,4871-4885. |
| Native modules | Process | native_module_scope, target maps/Funcs, constructors' allocations | Funcs borrow permanently loaded code; modules never dlclose. Request selects module order. src/meta-native.x:995-1001,1138-1178. |
| Staged meta statics | Process-held detached scope slot | session_meta_scope allocations from module reset | src/meta-group.x:891-916; no explicit destruction or reset of this slot found. See gaps. |
| MetaContext call frame | Synchronous evaluation | Current site/evaluator values temporarily installed | Borrows Compiler; restored by $let after evaluation. src/macros.x:4265-4277. |

Map and Array copies isolate containers, not their reachable payloads. Map stores
Var bits and does not destroy payloads (lib/map.x:12-15); Array explicitly documents
shallow copy (lib/array.x:7,33). Therefore copying a map that contains nested mutable
maps is not deep isolation. Cache retention is an explicit separate operation.

## Traced operations and child modes

1. Ordinary unit: frontend opens isolated Context, begins Type unit table, creates
   Compiler, attaches borrowed request SourceView and unit source-fact stores.
   Collection and full parse share Context. close frees Lisp before canonical
   Pool release, NULLs Type unit slot, and releases Context. Evidence:
   [frontend.x:192](../../src/frontend.x#L192),
   [frontend.x:198](../../src/frontend.x#L198),
   [frontend.x:157](../../src/frontend.x#L157).

2. Segment shadow: new_shared creates fresh tables/Sym/diagnostics, sharing unit
   identity and package handles. prepare installs provider hash table, lexical
   mode, macro/literal/session handles and shifts token coordinates. Parsing
   returns replacement segment handles to owner; declarations/statics/deps merge.
   close_child does not free compiler allocation. Evidence:
   [collect.x:339](../../src/collect.x#L339),
   [compiler.x:2636](../../src/compiler.x#L2636),
   [fields.x:32](../../src/fields.x#L32).

3. Cold included file: new_shared keeps unit binding identity/package/shared
   source records, but configure_package may detach package_roots. It uses a
   fresh Lisp/effect state unless library filling. globs are shallow copied;
   active cycle-prefix arrays are shared into fresh visited map. _walk_apart
   temporarily replaces names.counters on the shared GenNames record while
   next_binding remains shared. Evidence:
   [collect.x:591](../../src/collect.x#L591),
   [collect.x:580](../../src/collect.x#L580),
   [collect.x:617](../../src/collect.x#L617).

4. Package compiler: caller registers root before constructing child, so normal
   shared package_roots identity supplies package scope. Package child builds
   cached public surface; caller merges definitions/deps and retains public
   effects. Evidence: [collect.x:1272](../../src/collect.x#L1272).

5. Default-selection shadow: fresh Sym overlay over collected file symbols;
   borrows owner's Lisp and meta group; rebuilds protocols, resets conforms;
   merges selected declarations/statics/definitions back. Evidence:
   [compiler.x:895](../../src/compiler.x#L895),
   [compiler.x:921](../../src/compiler.x#L921).

6. Import replay shadow: take_unit_state, reset symbols, start collection,
   replay imports, return_unit_state and merge dependencies. Evidence:
   [collect.x:1465](../../src/collect.x#L1465).

7. Host CPP compiler: new_shared, separate tokenizer/line markers, retained
   inside ParsedUnit; borrows imports/Lisp/meta group explicitly. Source facts
   disabled because merged CPP offsets do not describe physical files. Evidence:
   [frontend.x:395](../../src/frontend.x#L395),
   [frontend.x:437](../../src/frontend.x#L437).

8. Delayed inline provider: a cold provider with private types and public inline
   bodies is queued as pointer plus original text/symbols/statics/hash state.
   public_bodies suppresses close_child's free_lisp. After graph completion the
   same compiler replays signatures, tokenizes original text, binds bodies,
   publishes dependencies, clears public_bodies and closes. This is deliberately
   longer than one child call, still bounded by unit Context. Evidence:
   [collect.x:966](../../src/collect.x#L966),
   [collect.x:995](../../src/collect.x#L995),
   [compiler.x:2618](../../src/compiler.x#L2618).

9. Meta-group emission is not a new_shared child. Backend needs more owner state
   than the child constructor copies. It snapshots entire Compiler and GenNames,
   begins semantic transaction, copies named mutation targets, resets fresh
   output state, runs lowering/generation, restores structs, then rolls back.
   Its result must remain allocated after restore. It shares inherited pointers
   not explicitly copied; those must not acquire unrolled-back mutation.
   Evidence: [meta-group.x:210](../../src/meta-group.x#L210),
   [meta-group.x:283](../../src/meta-group.x#L283).

10. Collection macro production copies name counters and retains the copy only
    when retaining generated declaration production. Ordinary repeated expansion
    restores original counters while retaining required helper declarations.
    Evidence: [compiler.x:633](../../src/compiler.x#L633).

11. Builtin/shipped definition child: _install_source replaces child.sym,
    fn_defs, macros and kw_aliases with the owner's exact handles. Its fresh
    Sym becomes unused Scope storage. Sym.c still names the owner, so diagnostic
    ownership differs from ordinary fresh-Sym children. Child tokenizer and
    diagnostics remain local. Evidence:
    [macros.x:4729](../../src/macros.x#L4729).

12. Shared-surface preload: frontend uses a nonisolated named Context, not an
    ordinary private canonical pool. It attaches borrowed shared Lisp and closes
    that unit after installing meta builders. This preserves canonical values
    for the shared session while its mutable parser state stays temporary.
    Evidence: [frontend.x:479](../../src/frontend.x#L479).

13. REPL external consumer: ReplSession borrows a persistent Compiler until
    ParsedUnit.close. It owns a separate Lisp evaluator and lowering service;
    ReplSession.close releases those before the caller closes the compiler unit.
    Results, completion candidates, original canonical inspection Lists and
    published name state borrow the persistent unit. Source facts are explicitly
    disallowed because submission scratch symbol maps are reclaimed per call.
    Evidence: commands/repl/repl-session.x:10-38,70-85,100-105,554-560.

    Submission and completion use a detached scratch Scope. _ParserInput saves
    tokenizer, token, input_boundary, directives_taken, text, arm_stacks,
    layout_marks and packed_marks. Both defer restoring that record; braces is
    saved/restored separately for region checking. A semantic transaction is
    begun with scratch storage and deferred rollback; successful submission
    publication is a distinct operation. Persistent semantics therefore outlive
    temporary parser input. Evidence: commands/repl/repl-session.x:108-139,
    211-228,391-407. Changing Compiler field structure must preserve this
    external consumer's precise temporary-input boundary.

## Bounded failure-path ordering

### Segment failure before return_unit_state

FileWalk.parse constructs shadow, installs defer close_child, prepares state,
then shallow-parses. return_unit_state and dependency/declaration merges occur
only after shallow parsing returns (src/collect.x:339-346).

If parsing transfers before return, close_child first takes diagnostic rows,
then invokes free_lisp unless public_bodies is set. A segment shadow starts with
public_bodies zero. If it borrowed an existing Lisp, free_lisp does not destroy
that owner session. If it created a new Lisp from a NULL inherited handle,
borrowed_lisp remains zero and close_child destroys that shadow-owned session.
The owner has not received the handle, so no transferred ownership is lost.
free_lisp NULLs an owned destroyed session, preventing finalizer double cleanup
(src/compiler.x:2618-2620,2636-2650,2824-2836; src/macros.x:4252-4258).

Replacement segment handles are not copied back after the failure. Already
shared map mutations can remain, but the failed collection does not continue
to the next segment: malformed propagates to ParsedUnit.collect, which returns
failure; open_reporting then closes unit. Frontend.open's caller must close on
either result (src/frontend.x:87-106,128-140). This is correct session cleanup
for aborted collection, not an unresolved escaped-Lisp obligation. It does not
prove semantic rollback of each map; that requires mutation-path analysis.

### Deferred inline-provider failure

queue_public_bodies marks the provider public_bodies=1 and stores its Compiler
pointer in the unit queue. The original cold-walk defer then takes diagnostics
but deliberately leaves its owned Lisp alive. bind_pending_inline_bodies removes
the queue row before replay and full parse. Normal completion clears the flag
and closes provider (src/collect.x:985-988,1000-1017).

If replay, tokenization, binding or publication transfers, the normal explicit
close is skipped. The removed queue row is not the allocation owner: provider
Compiler remains a finalized Scope allocation in the owning unit. Unit close
releases the Context and eventually runs _drop_compiler, which calls free_lisp
without checking public_bodies. Thus the owned Lisp has finalizer fallback even
when the queue row has been removed. Providers still queued have the same
fallback. Borrowed library Lisp is not destroyed by those finalizers.
Evidence: src/compiler.x:2766-2768,2824-2836; lib/scope.x:137-147,618-632;
src/frontend.x:157-164; lib/context.x:331-349.

This fallback occurs after Context Pool release, unlike normal explicit Lisp
cleanup. Lisp.destroy reclaims detached user/session Scopes (lib/lisp.x:1811-1814).
No active Lisp evaluation is left on this source-level transfer path. This
lane does not establish whether every possible user-installed finalizer in a
Lisp scope can avoid reading expired canonical payloads during fallback. That
is the remaining precise teardown-order question; no leak or invalid read was
reproduced. The provider allocation and destruction responsibility are known.

## Coverage limits

The inventory covers all Compiler fields and the listed lifecycle paths. It is
not an exhaustive inventory of every reachable mutation. No failure-path, leak,
concurrency, performance, or behavioral equivalence probe was run.

The process-held `session_meta_scope` has no explicit teardown at its two source
uses. Its complete shutdown behavior remains unverified; this is not a leak finding.

## Plan review

This reference retains existing allocation, borrowing, transfer, and retention
boundaries. It introduces no implementation, validator, diagnostic, fixture,
or recurring process. Future grouping must preserve replacement and aliasing
exceptions recorded above.
