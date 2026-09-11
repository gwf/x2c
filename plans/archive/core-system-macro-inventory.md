# Core system-macro adoption inventory

> Status: done
> Historical evidence archived with the compatible adoption, 2026-09-11.
> Expanded read-only inventory supporting core-system-macro-adoption.md.
> Source baseline 8eb27f4bb2fad4d1ec179ed6fd9c1a3230b01a62, 2026-09-11.
> Historical inventory; implementation results and staging correction are
> recorded in core-system-macro-adoption.md. Source rows retain baseline lines.

## Scope and counting

Inspected all 87 authored .x/.xmacro files under src/ and lib/ (including
macro templates), excluding generated lib/x2c.x from adoption counts. The
src area contains 30 .x files and one xmacro. Scanner results were review
queues: manual review traced producers, receivers, aliases, helper bodies,
registration points, cleanup bodies, early exits and escaping values.

- Every executable defer: 81 src and 108 lib/templates; the companion
  [defer audit](core-system-macro-defer-audit.md) records all 189 individually.
  A second mask-preserving token census confirms no inline defer was missed;
  the other 17 src tokens and one lib token are AST/scanner data.
- Saved-state candidates: 61 src and 18 lib regions, 118 restored-place
  occurrences. Compatible 30 regions/40 places; consequential 30/52;
  rejected 19/26. A multi-field region is not several independent regions.
- Destination candidates: 7 src and 23 lib logical regions, including five
  callers of Error's conditional wrapper instead of counting its implementation
  again. Compatible 9; staging exclusion 1; consequential 12; specialized 8. No executable
  handwritten retain/release region remains beyond existing macro adoption.
- Auto-compatible owners: 18 src and 28 lib. The source raw census counts
  call expressions; the library raw screen counts cleanup-bearing source lines
  plus two indirect finisher sites. They are explicitly separate units, never
  one summed migration count. Existing macros are not additional opportunities.

C = source-confirmed contract-compatible with the documented rewrite;
E = feasible but changes failure restoration, cleanup registration/order, or
requires a consequential ownership decision; R = preserve current semantics
or reject low-value mechanical churn. Source confirmation does not claim an
unimplemented migration passed full integration tests.

## Expanded src cleanup inventory

All 30 src/*.x files and src/ast-rewrite.xmacro were screened with comments
and strings masked. Every executable defer has an individual row in the
separate defer audit. AST construction containing the symbol defer is not an
executing cleanup in the compiler. Native functions and parent-aware helper
cleanup were included, not only receiver.free spelling.

### Reproducible raw census

The screen finds 446 cleanup/consumption call expressions across 28 .x files
(the other two source files and the xmacro have none). This is a CALL count,
not unique locals or suggested edits. A line can contain two calls; several
success/error exits can consume the same local. Do not sum this with the
library's source-LINE screen. The detailed per-file counts follow below.

- 262 list_free, 8 str_free, 14 string_close: 284 consuming-call boundaries.
- 90 free, 43 close (method/native), 4 fclose, 2 closedir, 5 destroy: 144
  allocation/resource cleanup calls, including owners and field destructors.
- 7 close_child, 2 free_lisp, 5 bootstrap_release, 4 Build.cleanup calls:
  18 specialized lifecycle calls.

### Compatible initialized locals: 18

Seventeen ordinary adjacent declaration/defer pairs:

| File | Deferred-call lines | Owners |
| --- | --- | --- |
| ast.x | 99 | pending |
| build.x | 865 | per-entry Context context |
| cache.x | 481 | pending |
| compiler.x | 1481 | heads |
| emit.x | 1420,1593,1612 | pending, pieces, emitted |
| expressions.x | 689 | pending |
| generate.x | 673 | resume |
| lambda.x | 992,1054,1087 | resume, pending, pending in separate functions |
| macros.x | 1330,1495 | rewritten Buffer, items Array |
| main.x | 430 | target Context |
| transform.x | 1409,1570 | suffixes, transformed |

One nonadjacent compound cleanup: statements.x:230-242, _match_case captures.
Move `Array captures = $auto(%[]);` into the existing inner block. Keep the
state-restoration defer after its declaration so match_types and in_pattern
restore before Array cleanup. Capture allocation still precedes those state
changes; its Array does not escape, while types = captures.list() is copied
canonical storage. This can compose with the two-field let region; count one
managed local and one let region, not two independent function rewrites.

### Eight additional deferred Array owners: failure timing differs

emit.x:257-259 pending/modes, :384-387 resume/resume_try, :1571-1574
operators/rights, and transform.x:1626-1629 levels/types acquire both Arrays
before registering either defer. Registering auto at each declaration releases
the first Array if the second initialization fails. Existing code retains it
in the enclosing Scope. Replacing only one defer can also reverse cleanup
order. These are four concrete paired regions, eight possible managed locals,
not eight exact-equivalence changes. Keep them separate from the 18 above.

### Nondeferred and consuming paths: reviewed distinctions

The large consuming-call count is real, but these APIs already combine
conversion and protected release. An initializer plus list_free/str_free
usually becomes an initializer plus list/str: zero statement deletion, earlier
failure registration, and possibly later release. Do not bulk change these
284 calls to inflate the adoption count. Calls in for headers, interpolation,
arguments, chained expressions, and return expressions have an earlier release
point than the enclosing function's defer. Use a new narrow block only when it
simplifies an actual owner; include its source cost and result-local hoisting.

Concrete high-deletion follow-up candidates (not claimed equivalent):

| Owner | Existing cleanup | Before/after consequence |
| --- | --- | --- |
| ast.x:209-222 initializer_functions.functions | two rejected-arm frees, then list_free | auto can delete both duplicated frees and use list(); additionally cleans scratch on a nested Error |
| expressions.x:2804-2820 _initializer_layout.children | two rejected-layout frees, then list_free | same useful duplication removal; returned canonical layout survives scratch release |
| expressions.x:3135-3163 _initializer_adapters.prepared | three rejected-choice frees, then list_free before adapter loop | narrow block must end before adapter construction, preserving release before the later loop; hoist canonical choices; adds earlier Error cleanup |
| transform.x:1329-1385 _lower_callable_defer.records | unsupported and completed frees | auto removes both exit copies; keep captures Map and canonical record_list ownership separate; exact successful free boundary precedes final AST construction |
| project.x:497-507 _target_sources.expanded, twice | explicit free at end of each loop body | auto stays per iteration; adds cleanup if contains/push raises; never manage returned kept Array |

Additional explicit scratch locations reviewed, all requiring an error-lifetime
or early-release decision rather than an automatic replacement:

- cache.x:392,647 (local dependencies), :693 (initializers);
  cli.x:558 (token Buffer), :834-835 (includes/cpp Arrays);
  collect.x:161 (dirs), :507 (segment), :838 (names).
- compiler.x:1609 typed Array has early failure returns and optional canonical
  tags output. generate.x:254 queue and :534 candidates; deps.x:73 word Buffer
  and :160 paths; emit.x:1276 heads.
- literals.x:219,237 elements, :463 symbols converted from List, :499-500
  symbols/tokens, :556 args, :616 pair, :620 elements. Respect runtime_literals
  and in_pattern restoration after cleanup, and per-iteration pair lifetime.
- main.x:367 chunks must be freed before later progress state; project.x:519-520
  sources/excluded end before kept.sort; protocol.x:841 members (failure branch
  plus later consuming path), :977 resolved, :1435 names, :1927
  parameter_bindings, :2302 ordered; snapshot.x:89 entries has an earlier
  write-failure return currently leaving scratch to Scope; statements.x:260
  locals ends after symbol-scope binding, before guard parsing.
- expressions.x:3286-3297 converted/captured have branch frees and sequential
  successful consuming calls. A blanket auto at function exit crosses the
  native-identity continue boundary and changes scratch/diagnostic ordering.

Concrete rejections that a simple scanner misses:

- cache.x:509 ids escapes on success; :595 and :654 free consumed PARAMETERS
  owned by callers. expressions.x:2692 states is likewise a consuming parameter.
  These are not initialized-local ownership. Moving ownership to callers is
  an API/lifetime redesign, even though those APIs are private.
- compiler.x:1623 MatchCaptureLayout has free but no Cleanup adoption. Do not
  invent a general free-method inference or new protocol solely for spelling.
- frontend.x:374 diagnostics.entries is temporary FIELD storage, merged then
  replaced by collected; emit.x:1921 state.cleanups is a stack record's field.
  A field cannot use auto. Extracting a local would need alias and ordering
  review, not deleting the field cleanup in place.
- File acquisition may use nullable fopen; File.cleanup delegates to fclose
  and is not null-safe. _read_marker, _state_file, _state_matches,
  _installed_tool and SourceView/read helpers therefore cannot simply wrap
  the existing initializer. Keep close-before-report/string conversion and
  close result checks. Artificial success-only managed aliases generally
  cost more code than the one explicit close they replace.
- bootstrap extraction/recording, depfile publication and compile-command
  output inspect close status before validating or renaming; auto discards
  that result. _write_outputs additionally borrows Stdout and must not close
  it. ChildProcess owns FILE handles across start/wait and closes both before
  status publication. Directory handles have no Cleanup contract.
- native free of cwd, resolved paths, manifests, translation/build worker
  arrays and normalized multiline-string bytes preserves the actual allocator.
  Raw pointers do not acquire Cleanup from their allocation spelling.
- close_child takes parent and child, retains diagnostics, and releases only
  owned Lisp registration; Compiler.free_lisp tracks a shutdown list and
  borrowed Lisp. ParsedUnit.close needs an out-parameter result and staged
  subresource cleanup. Build.cleanup(success) depends on result policy;
  bootstrap_release removes a held filesystem lock while retaining payload.
  None is ordinary one-value initialized-local destruction.

No class/representation/adapter change is recommended as a prerequisite.

### Raw source call census by file

| File | Consuming calls | Direct cleanup calls | Lifecycle helpers | Total |
| --- | ---: | ---: | ---: | ---: |
| src/ast.x | 1 | 3 | 0 | 4 |
| src/bootstrap.x | 1 | 10 | 1 | 12 |
| src/build.x | 7 | 7 | 0 | 14 |
| src/cache.x | 14 | 7 | 0 | 21 |
| src/cli.x | 11 | 8 | 0 | 19 |
| src/collect.x | 14 | 5 | 2 | 21 |
| src/compiler.x | 14 | 7 | 2 | 23 |
| src/deps.x | 1 | 3 | 0 | 4 |
| src/editor.x | 0 | 7 | 0 | 7 |
| src/emit.x | 29 | 11 | 0 | 40 |
| src/expressions.x | 35 | 9 | 0 | 44 |
| src/format.x | 1 | 0 | 0 | 1 |
| src/frontend.x | 1 | 3 | 3 | 7 |
| src/generate.x | 7 | 5 | 0 | 12 |
| src/lambda.x | 20 | 3 | 0 | 23 |
| src/literals.x | 12 | 10 | 0 | 22 |
| src/macros.x | 21 | 4 | 2 | 27 |
| src/main.x | 1 | 9 | 8 | 18 |
| src/parse.x | 30 | 0 | 0 | 30 |
| src/project.x | 9 | 5 | 0 | 14 |
| src/protocol.x | 20 | 5 | 0 | 25 |
| src/snapshot.x | 0 | 3 | 0 | 3 |
| src/sourceview.x | 1 | 1 | 0 | 2 |
| src/statements.x | 5 | 2 | 0 | 7 |
| src/toolchain.x | 6 | 2 | 0 | 8 |
| src/transform.x | 19 | 7 | 0 | 26 |
| src/type.x | 4 | 0 | 0 | 4 |
| src/utils.x | 0 | 8 | 0 | 8 |

## lib $auto ownership inventory (planning only)

Inspected all hand-authored lib/*.x and lib/*.xmacro (not generated x2c.x),
including underscore native aliases, conditional frees, consuming helpers,
nonadjacent explicit cleanup, and backing-field destruction. The library survey was read-only. A subsequent isolated map-template probe
is recorded below; source-contract confirmation is not whole-tree migration
validation.

### Counts and units

Raw screening: 211 comment-stripped source lines containing a free/destroy/
close/cleanup operation or helper, excluding declarations, direct Cleanup
adapters, and the misleading `_cache_free_slot` lookup. The complete list is
the per-file count table and named families below. Add TWO indirect consuming calls in
array-generics.xmacro:722,729, traced through `_array_finish_buffer` in
typed-array.x:85: **213 raw screening lines**. These are not 213 independent
resources: e.g. success/failure cleanup for one local is two lines; field
teardown and native helpers are deliberately included. Macro definitions count
once, never once per generated family. Same-line Lisp.destroy and _array_finish_buffer bodies are included as actual
cleanup calls, not discarded with their function headers. Public consuming implementations remain
in this raw screen, because their caller ownership also needs inspection.

Of these lines, 28 are confirmed replacement sites for 28 initialized locals;
12 correspond to 12 plausible local replacements that expand error cleanup;
173 are rejected from the immediate migration set (including low-benefit
mechanical possibilities). This arithmetic is by source cleanup site, not
runtime allocation or generated function count. The 28 and 12 happen to have
one relevant raw cleanup line each. Do not add runtime template instantiations
to these authored counts.

| Area | Raw lines including indirect helpers | Compatible locals | Expanded error cleanup locals | Other/rejected lines |
|---|---:|---:|---:|---:|
| list.x | 17 | 16 | 0 | 1 |
| array.x | 7 | 2 | 1 | 4 |
| file.x | 11 | 2 | 0 | 9 |
| lisp.x | 12 | 5 | 1 | 6 |
| map-generics.xmacro | 14 | 3 | 2 | 9 |
| array-generics.xmacro | 7 | 0 | 2 | 5 |
| atom.x + symbol.x | 2 | 0 | 2 | 0 |
| split.x | 2 | 0 | 2 | 0 |
| string.x | 12 | 0 | 1 | 11 |
| lib.x | 4 | 0 | 1 | 3 |
| all remaining lib files | 125 | 0 | 0 | 125 |
| TOTAL | 213 | 28 | 12 | 173 |

### Confirmed: 28 exact initialized-local cleanup contracts

- list.x:324,343,366,441,542,556,570,669,699,725,809,823,859,861,1105,1121:
  sixteen Arrays, same original initializer, block, and defer registration.
- array.x:555,557: source/target Array scratch. Swap aliases are intentional;
  defer and $auto both observe final binding, so both allocations free once.
- file.x:486,511: line/content Blocks, same region and copying into canonical
  String before destruction.
- lisp.x:517: move `tokens_scope = Scope.new_named("Lisp tokens")` into the
  EXISTING inner block, keep Symbol status outside, replace that inner destroy
  defer. No intervening side effects between acquisition and existing block.
- lisp.x:899: `_call_lambda` frame Scope; Map bindings = NULL initialization
  cannot raise. Preserve frame destroy after evaluation and destination pop
  before evaluation. Do not auto-free bindings independently.
- lisp.x:1036: move File source acquisition into EXISTING inner block, leave
  result outside, use $auto. Close remains before function return.
- lisp.x:1603: eval_string tokens Scope; direct initialized local and immediate
  destroy; returned canonical evaluation values retain current owners.
- lisp.x:1630: eval_file content Block; direct initializer/immediate free.
- map-generics.xmacro:132,135: `_core_expand` staged_hashes/staged_entries
  Bytes, found through Bytes_free aliases rather than method spelling.
  $auto(Bytes_new(...)) follows existing Bytes Cleanup. Preserve assignment of
  Bytes_append's possibly relocated pointer. Both locals become zero after
  their backing storage is moved/published; final-binding cleanup remains a
  null no-op. This is ALREADY unconditional defer with cancellation by null,
  unlike the failure-only staged exports elsewhere. Acquisition registration
  is already individual and properly ordered. Existing explicit frees of old
  hashes/entries stay explicit; those aliases are map-owned before commit.
- map-generics.xmacro:580: comparison scratch Scope, existing direct defer.

The last three generic sites were absent from the original plan. They are
three authored sites shared across map families; count three, not the number
of emitted functions. Native aliases and method cleanup ultimately reach the
same Bytes_free and Scope_destroy owners. A focused typed-map compilation
probe should verify macro definition ordering/import visibility before any
claim of executed migration parity.

Examples:

```x2c
// map-generics before
Bytes staged_hashes = Bytes_new(sizeof($hash_cell));
defer Bytes_free(staged_hashes);
staged_hashes = Bytes_append(staged_hashes, 0, capacity);
// after
Bytes staged_hashes = $auto(Bytes_new(sizeof($hash_cell)));
staged_hashes = Bytes_append(staged_hashes, 0, capacity);
// retain existing staged_hashes = 0 after publication
```

```x2c
// Lisp.read after; preserve the existing cleanup boundary
Symbol status;
{
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source + base, &tokens_scope);
  status = _read_tokenizer(tokenizer, source, base, cursor, out);
}
return status;
```

### Viable, separate error-lifetime decision: 12 locals

These preserve successful result ownership but free scratch earlier on raises
than the current code, which leaves it to the active Scope. They are not
strict error-lifetime equivalents and require explicit review of that choice.

| Source | Local | Current end | Proposed end |
|---|---|---|---|
| lib.x:89-94 | Array sizes | explicit sizes.free after sort | $auto + return sizes.sort() |
| lisp.x:310-328 | Array elements | explicit free after reader | $auto; remove explicit free |
| split.x:81-93,120-133 | Array results (2) | results.list_free() | $auto; results.list() |
| string.x:544-554 | Array results | results.list_free() | $auto; results.list() |
| array.x:714-723 | Buffer buf | buf.str_free() | $auto; buf.str() |
| atom.x:139-142 | Buffer out | out.str_free() | $auto; out.str() |
| symbol.x:195-198 | Buffer out | out.str_free() | $auto; out.str() |
| map-generics.xmacro:679-688 | Buffer out (2) | out.str_free() | $auto; out.str() |
| array-generics.xmacro:720-729 | Buffer out (2) | $finish_buffer(out) | see below |

The consuming calls already defer destruction *inside* list_free/str_free;
$auto moves registration earlier than the element/render construction loop,
covering errors before entering that helper. Canonical List/String output is
copied/interned; it does not alias the Array/Buffer backing allocation.
Callback side effects and retained external values are unaffected; scratch
lifetime on callback transfer changes. This is useful cleanup consistency,
not pure textual substitution.

Typed-array renderers use `$new_buffer`/`$finish_buffer` parameters to
`$array.typed.render`; current seven builtin family invocations pass
`_array_new_buffer` and `_array_finish_buffer`. Replacing the shared finisher
with nonconsuming Buffer.str silently changes that internal helper contract.
If approved, edit both macro body managed initializers and its passed finisher
atomically, preserve any external macro invocation contract, or specialize the
built-in usage through a separate nonconsuming parameter. Do NOT claim these
two sites as ready for automatic rewriting. The 14 expanded functions from
seven types remain only two source candidates.

### Rejected and lower-value families (all remaining raw entries)

- iter.x:161-163 `removed`: an initialized Array with immediate free. It CAN
  become `$auto` in a new tiny block ending before `heads[column] = 0`, but
  deletes no substantive plumbing and adds braces. Function-wide defer delays
  the lifetime across that update. Keep explicit immediate discard (1 line).
- array.x:457,474,799; typed-array.x:95; typed-map.x:359,394;
  array-generics:692,771; map-generics:273,286,814,833: failure-only scratch
  frees protect values that escape on success or a borrowed existing map.
  Plain $auto would destroy the returned/published object. A null-disarm rewrite
  is possible for some, but adds a second owner binding or assignment rather
  than deleting machinery. Preserve transfer flags and cleanup order.
- array-generics:248 source can be borrowed or a self-alias copy. The copied
  flag determines ownership. Unconditional cleanup destroys caller storage.
- array-generics:805,823 staged export swaps buffer ownership; map-generics
  export does equivalent old-table swapping. Keep publish/commit flag checks.
- map.x:450,451,469,470: first two failure-only staged Bytes and two old-table
  aliases. The first acquisition currently is not protected until the second
  succeeds. Per-initializer auto changes allocation-failure cleanup and cannot
  free old-table aliases before successful commit. Could be separate designed
  rollback simplification; not this exact set.
- file.x:185,186,207,215: String first may become canonical output, content
  starts NULL and is acquired later. Combined defer runs String before Block;
  auto declaration order could reverse that. Explicit frees disarm aliases by
  NULL. String has no general owning Cleanup (canonical ownership differs).
  A selective content-only rewrite can preserve order by retaining manual
  first defer, but offers little deletion; never apply auto to both.
- file.x:388 uses `owned = result` and NULL to transfer interned storage. Same
  missing general String Cleanup and owner-transfer reason.
- file.x:526,554: line is iterator state or transferred into it; keep flag
  prevents destroying live iterator storage. $auto does not transfer ownership.
- file.x:226, list.x:592, buffer.x:338: public consuming *parameter* APIs;
  `$auto` is initialized-local-only. Creating artificial local aliases adds
  plumbing and does not improve their implementation. Keep APIs; change
  selected owning callers only in the separate tier above.
- lisp.x:705 path.open().string_close already expresses consuming ownership;
  introducing a managed local expands a correct one-line API. lisp.x:716
  tests File.close status; File Cleanup discards it, so would change result.
- lisp.x:457,866; func.x:281; context.x:118-124: construction rollback returns
  owning handles on success and performs ordered component cleanup on error.
- error.x:554 Block pairs is tempting explicit local cleanup but executes in
  `floor_only` error construction, before `_scope_push` pop/record publication.
  Adding exception cleanup machinery inside error infrastructure needs an
  independent correctness argument. Do not migrate as ordinary scratch.
- error.x:974,978 Var* values is an explicitly allocated native array, freed on
  both match/no-match paths before List pool release/handler publication.
  Raw pointer has no Cleanup. `_region_destroy(&view)` at 1011 owns copied
  ErrorRegion contents with custom destruction, not a Cleanup value contract.
- error handler frees/pops, retained ErrorRecord loops, Error shutdown,
  exception `_cleanup_drain`, Context close and thread worker Context are
  lifecycle machinery. Thread's work.close at 153 follows try/catch handling
  but precedes result-pool detachment, destination pop, Error shutdown. A broad
  function $auto gets this order wrong; a new block also adds cleanup on
  previously uncovered errors in capture/catch. Preserve explicit order.
- buffer.x:192 char* bytes; array.x:603 entry array; var.x:436,537 box rollback;
  match.x native lower.sites and scratch: no matching owning Cleanup on raw
  pointer. Switching representation to Block/Bytes is a separate allocation
  layout/API choice, not adoption of existing ownership.
- match-recursive.x:254,269 layout has success and malformed exits but no
  Cleanup adapter; MatchPlan/MachineProgram likewise only free methods.
  Adding Cleanup participation is a separate API change; moving frees also
  adds early failure cleanup. Cache eviction/replacement frees plan aliases
  according to cache/site ownership, not local declaration lifetime.
- scope.x raw chains/names/stack/hooks and pool.x blocks/index/native state,
  static-init guard payload, thread native handles use native frees, conditional
  locks or finalizer ordering. They cannot use Scope-backed cleanup blindly.
- pthread_mutexattr_destroy in dispatch/logger/pool and mutex destroy in
  Mutex.free concern native objects and partial initialization; `$lock` is not
  destruction, and Mutex Cleanup does not apply to pthread attributes.
- string.x `_free_unchecked`/pool free/intern_free and mutable construction
  macros distinguish uninterned buffers, canonical objects, pool ownership,
  and successful transfer. General String auto-cleanup would violate those
  distinctions.
- Remaining block/buffer/machine/map/lib/logger/context/match/thread teardown
  sites free a receiver or its fields, backing arrays, cache members, worker
  results, or callback-owned state. There is no initialized local ownership
  interval to abbreviate. Existing Cleanup adapters are excluded from counts.
  Custom destroy callback invocation is not a type cleanup method.

Inspection-only negative coverage: error-macros.xmacro contains no matching
resource release operations; cleanup behavior is in error.x and exception.x.
All unmatched files contributed zero cleanup screen hits; that does not claim
absence of every imaginable new lifetime policy, only no handwritten release
counterpart in this systematic cleanup/helper search.

## Systematic $let inventory (read-only source review)

Baseline source: 8eb27f4. Handwritten top-level src/*.x and lib/*.x, excluding
lib/x2c.x. Searched all old/previous/saved/enclosing/prior references, every
deferred assignment/block, matching local-save/field-restore assignments even
without those names, and paired state-depth increments/decrements. Inspected
helper-mediated restoration and conditional return paths. No let migrations/probes were executed for this state inventory.

A region is one logically bounded override, possibly with multiple fields;
overlapping regions with distinct endpoints count separately. Restored places
are per-region counts, not distinct global field names. C = compatible with
existing exit behavior; E = feasible but adds or moves failure restoration or
requires a consequential conditional/ownership choice; R = rejected direct
substitution. Snapshot `$let(place, place)` is included, not discarded for a
redundant initial assignment. Large bodies are included.

### Counts

| Area | C regions/places | E regions/places | R regions/places | Total regions/places |
| --- | --- | --- | --- | --- |
| src | 26/36 | 28/50 | 7/14 | 61/100 |
| lib | 4/4 | 2/2 | 12/12 | 18/18 |

### Region ledger

| ID | Source and function | Places | Class | Decision and exact boundary |
| --- | --- | --- | --- | --- |
| L01 | `src/parse.x:423` Compiler.parse_field | 1: aggregate_type | C | Direct replacement; keep exact short body. |
| L02 | `src/parse.x:520` Compiler.parse_enumerator | 1: aggregate_type | C | Direct replacement; keep exact short body. |
| L03 | `src/parse.x:1544` _finish_aggregate_type | 1: aggregate_type | E | Direct replacement. At 1544 hoist bound acquisition; existing allocation precedes restoration registration. |
| L04 | `src/parse.x:1318` _finish_function_parts | 2: return_type, fn_name | E | Nested lets around existing symbol scope; keep pop before field restoration. Earlier protection includes push_scope failure. |
| L05 | `src/parse.x:1836` Compiler.bind_syntax | 1: return_type | C | Whole remaining function body; size is not an exclusion. |
| L06 | `src/parse.x:1920` Compiler.bind_syntax function recipe case | 1: macro_stack | C | Use thaw_declaration_syntax replacement; retain recursive return inside decorator. |
| L07 | `src/parse.x:1001` _test_declaration_start | 1: token | E | Snapshot then lookahead; use let(token,token), retain early return behavior and end before result tests. New unwind restoration. |
| L08 | `src/parse.x:1027` _test_declaration_group_comma | 1: token | E | Snapshot-only lookahead; let(token,token), next and recognizer inside. |
| L09 | `src/parse.x:2053` Compiler.bind_syntax function case | 1: params | R | Restoration obtains sym.pop_scope result, not saved prior field value. |
| L10 | `src/literals.x:304` Compiler.parse_list_literal | 2: match_is, match_types | E | Two normal restoration paths. Conditional quote replacement preserves original match_types otherwise; end before _build_cons_cell. Adds error restoration. |
| L11 | `src/literals.x:524` Compiler.parse_raise_literal | 1: runtime_literals | E | Whole parser body to restoration; adds error restoration. |
| L12 | `src/literals.x:575` Compiler.parse_catch_pattern_literal | 2: in_pattern, runtime_literals | E | Two nested lets; documented current contract says restored on success. Adds error restoration. |
| L13 | `src/literals.x:994` Compiler.capture_lambda_identifier | 1: lambda_scopes | E | Use snapshot let(place,place), then retain chain-search and resolution. Registration moves before search. |
| L14 | `src/literals.x:1072` Compiler.bind_lambda_expression | 1: lambda_scopes | E | Snapshot let(place,place) wraps begin/end capture operations unchanged; protects begin failure earlier. Do not remove capture helpers. |
| L15 | `src/literals.x:1172` Compiler.parse_lambda_literal | 1: lambda_scopes | E | Same snapshot idiom around begin/end and complete remaining body; preserve params scope behavior. |
| L16 | `src/literals.x:1179` Compiler.parse_lambda_literal compound body | 1: return_type | C | Direct replacement with Var type. |
| L17 | `src/compiler.x:615` _shallow_parse_compile_time_definition | 5: recovery_depth, diag.emit, diag.owner, diag.count, diag.limit_notified | E | Grouped speculation; emitter helper sets two plain fields. Keep entries.resize and caught-malformed semantics. Snapshot count/limited lets could restore on other errors too. |
| L18 | `src/compiler.x:847` Compiler.run_declaration_effects | 1: filename | E | Snapshot let then conditional filename assignment. Keep import_stack take_last before restore; earlier push failure protection. |
| L19 | `src/compiler.x:897` _produce_declaration_rows | 2: macro_stack, source_private | C | Parent implementation keeps stack outer and privacy inner: thaw runs under original context, and reversed adjacent restoration stores have no observer or callback. Parent review accepted this equivalent nesting without an extra temporary. Keep complete case inside. |
| L20 | `src/compiler.x:928` _select_declaration_rows | 2: macro_stack, source_private | C | Parent implementation keeps stack outer and privacy inner: thaw runs under original context, and reversed adjacent restoration stores have no observer or callback. Parent review accepted this equivalent nesting without an extra temporary. Keep complete case inside. |
| L21 | `src/compiler.x:1004` _select_declaration_forwards | 1: source_private | C | Complete declaration-forward case. |
| L22 | `src/compiler.x:1126` _shallow_parse_unit_macro | 2: names.counters, names.gensym_count | R | Early retained return intentionally keeps staged names. Unconditional let would undo committed retained declaration effects. |
| L23 | `src/compiler.x:1368` Compiler.full_parse | 1: recovery_depth | C | Whole existing braced parse region. |
| L24 | `src/collect.x:471` _file | 1: declaration_effects | C | Whole remaining function; effect restoration presently deferred. |
| L25 | `src/collect.x:470` _file alias maps | 2: kw_aliases, kw_seen | E | Separate overlapping region ending 544-545; both maps only restored normally today. Preserve all owner-copy checks and subsequent return. |
| L26 | `src/macros.x:511` _eval_string | 2: macro_import_compiler, macro_import_invocation | C | Nest invocation outer, compiler inner so compiler restores first, matching current restore order. Both replacements are plain locals; keep current try/catch inside. |
| L27 | `src/macros.x:1170` Compiler.evaluate_declaration_effect | 1: collect_protocols | C | Whole body after initialization. |
| L28 | `src/macros.x:1362` _eval_template_form | 6: macro_sdk_compiler, macro_sdk_source_file, macro_sdk_failure_message, macro_sdk_failure_notes, macro_sdk_source_captures, macro_sdk_has_references | C | Nest globals in reverse existing restore order; all replacement expressions are plain locals/null/boolean. Capture failure message/notes in outer result locals; leave six lets BEFORE report_error, preserving current early restoration and deleting duplicate explicit restores. |
| L29 | `src/macros.x:2057` Compiler.parse_macro_definition | 3: macro_holes, local_macro_captures, local_macro_capture_scopes | E | Overlapping regions beginning 2057 and 2170; keep pop_scope before restores. Retain boolean outer-holes fact for lines 2168/2279. Earlier parse failures now restore holes; requires diagnostic-recovery probe. |
| L30 | `src/macros.x:2630` Compiler.expand_macro_invocation_node | 1: token | C | Whole remaining with body; block scope defer remains outer. |
| L31 | `src/macros.x:2668` Compiler.expand_macro_invocation_node expansion body | 1: macro_stack | C | Snapshot let(place,place) preserves early restoration registration while actual replacement remains 2697. Use current stack in cons or retain saved value only if needed. |
| L32 | `src/macros.x:2710` Compiler.expand_macro_invocation_node bind step | 1: origin | C | Direct short replacement. |
| L33 | `src/macros.x:2929` _parse_target_definition | 1: token | C | Only transaction.commit inside override; later return outside. |
| L34 | `src/lambda.x:167` Compiler.lower_typed_adapter_expr | 1: origin | C | Case or remaining function; keep complete original restoration lifetime. |
| L35 | `src/lambda.x:179` Compiler.lower_typed_adapter_expr | 1: origin | C | Case or remaining function; keep complete original restoration lifetime. |
| L36 | `src/protocol.x:2329` _parse_protocol_member | 1: in_proto | C | Hoist declaration result; parser inside. |
| L37 | `src/statements.x:230` _match_case | 2: in_pattern, match_types | C | Keep captures free AFTER both restorations: outer block defer captures.free, nested lets inside. Acquisition still before overrides. |
| L38 | `src/statements.x:462` Compiler.parse_statement with case | 1: semantic_binding_facts[with-name alias] | R | Map presence-sensitive restore/delete and scope teardown; Map index is protocol operation, not stable addressable slot. |
| L39 | `src/statements.x:368` _optional_label_statement | 1: token | R | Successful label parse intentionally commits cursor; only failed alternative rewinds. |
| L40 | `src/transform.x:1690` _node at case | 1: origin | C | Keep occurrence for later bookkeeping. |
| L41 | `src/transform.x:1712` _node function case | 2: fn_name, inline_header | E | Whole transformed function construction; adds error restoration. |
| L42 | `src/transform.x:1829` _node raise case | 1: runtime_literals | E | Whole raise lowering, adds error restoration. |
| L43 | `src/emit.x:478` Emitter._function | 6: return_type, fn_name, volatile_names, label_paths, cleanup_path, static_objects | E | Overlapping regions; preserve first type emission before inner four overrides. Compute final fn name before installation or use snapshot let. New error restoration. |
| L44 | `src/emit.x:590` Emitter._block | 1: native_aliases | C | Snapshot let(place,place) deliberately useful despite no initial replacement: removes saved local/defer, retains mutations inside _emit. |
| L45 | `src/emit.x:775` Emitter._local_static | 1: cleanup_path | E | let(path,cons(ast,path)); end before list_free; adds error restoration. |
| L46 | `src/emit.x:1398` Emitter._initializer_macro | 1: compiler.source_map | C | Direct 0 replacement. |
| L47 | `src/emit.x:1642` Emitter._emit at case | 1: origin | E | After block refer to restored e.origin in source-map suffix, avoiding saved local. Adds error restoration. |
| L48 | `src/emit.x:499` Emitter._function barrier | 2: break_stop, continue_stop | E | Replace paired _cleanup_barrier_enter/leave helpers; capture cleanups.length once. Switch only changes break_stop, so its unchanged continue_stop need not get a let. Adds error restoration. |
| L49 | `src/emit.x:1774` Emitter._emit while | 2: break_stop, continue_stop | E | Replace paired _cleanup_barrier_enter/leave helpers; capture cleanups.length once. Switch only changes break_stop, so its unchanged continue_stop need not get a let. Adds error restoration. |
| L50 | `src/emit.x:1781` Emitter._emit do | 2: break_stop, continue_stop | E | Replace paired _cleanup_barrier_enter/leave helpers; capture cleanups.length once. Switch only changes break_stop, so its unchanged continue_stop need not get a let. Adds error restoration. |
| L51 | `src/emit.x:1793` Emitter._emit for | 2: break_stop, continue_stop | E | Replace paired _cleanup_barrier_enter/leave helpers; capture cleanups.length once. Switch only changes break_stop, so its unchanged continue_stop need not get a let. Adds error restoration. |
| L52 | `src/emit.x:1802` Emitter._emit switch | 2: break_stop, continue_stop | E | Replace paired _cleanup_barrier_enter/leave helpers; capture cleanups.length once. Switch only changes break_stop, so its unchanged continue_stop need not get a let. Adds error restoration. |
| L53 | `src/expressions.x:587` _parenthesized_cast_operand_follows | 1: token | E | Real temporary cursor replacement, adds restoration if lookahead raises. |
| L54 | `src/expressions.x:650` _is_type_selector_start paren branch | 1: token | E | Snapshot let around only successful c.test(open-paren) branch, preserve branch boundary; raises restore now. |
| L55 | `src/expressions.x:449` _parse_sizeof | 1: token | R | Alternative rewind only; successful declaration advances token. |
| L56 | `src/expressions.x:600` _parse_cast | 1: token | R | Alternative rewind only; successful cast returns consumed cursor. |
| L57 | `src/expressions.x:3002` _initializer_conversion | 7: key_ids, names.adapters, recovery_depth, diag.emit, diag.owner, diag.count, diag.limit_notified | R | Conditional completed/rejected rollback and diagnostic replay. Could isolate 3 unconditional fields, but restoring them must precede callback replay/transaction rollback; preserve specialized owner as a unit. |
| L58 | `src/frontend.x:293` _preprocess_input | 2: names.counters, names.gensym_count | E | Conditional !live_symbols region; needs branch factoring without duplicate work. Snapshot gensym, replace counters with copy; adds unwind restoration. |
| L59 | `src/frontend.x:368` ParsedUnit.parse | 1: diagnostics.entries | E | Canonical collected array stays outer; stage via let(entries,%[]), retain merge/free before restore. Non-malformed failures now restore original entries but temporary cleanup policy needs explicit choice. |
| L60 | `lib/lisp.x:1273` LispLower._auto_compile expanded branch | 1: depth | C | let(depth,depth+1) wraps recursive call; balanced nested lowering makes saved restore equivalent to decrement. |
| L61 | `lib/logger.x:330` Logger.flush | 1: emission_depth | C | Replace increment/deferred decrement by let(place,place+1); callbacks may recurse but cannot free/mutate owning lifecycle; preserve boundary before scratch reuse. |
| L62 | `lib/logger.x:463` _emit_text | 1: depth | C | Replace increment/deferred decrement by let(place,place+1); callbacks may recurse but cannot free/mutate owning lifecycle; preserve boundary before scratch reuse. |
| L63 | `lib/logger.x:710` Logger.log | 1: emission_depth | C | Replace increment/deferred decrement by let(place,place+1); callbacks may recurse but cannot free/mutate owning lifecycle; preserve boundary before scratch reuse. |
| L64 | `lib/match.x:902` MatchLower._compile_child | 1: depth | E | Return lowering result inside let(depth,depth+1); currently only normal exit decrements. |
| L65 | `lib/match.x:911` MatchLower._compile_child_segment | 1: depth | E | Return lowering result inside let(depth,depth+1); currently only normal exit decrements. |
| L66 | `lib/error.x:72` x2c_error_catch_push | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L67 | `lib/error.x:517` _record | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L68 | `lib/error.x:535` _record_n | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L69 | `lib/error.x:631` Error.snapshot | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L70 | `lib/error.x:652` Error.snapshot_in | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L71 | `lib/error.x:676` Error.since_in | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L72 | `lib/error.x:709` Error.since | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L73 | `lib/error.x:738` Error.policy_set | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L74 | `lib/error.x:956` _catch_match | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L75 | `lib/error.x:1012` _dispatch view | 1: floor_only | R | Error-floor guard is runtime infrastructure used during allocation/unwind. Do not register managed cleanup here without dedicated reentrancy/cleanup-stack design; preserve explicit increments/decrements and error floor. |
| L76 | `lib/error.x:1001` _dispatch handler chain | 1: handler_top | R | Restores explicitly before ExceptionFrame.unwind, fatal floor, and _leave; landing also restores watermark. Not ordinary lexical restoration. |
| L77 | `lib/lisp.x:1444` _auto_apply machine callback guard | 1: running | R | Clear-to-zero cleanup, not previous-value restore. |
| L78 | `src/parse.x:1878` Compiler.bind_syntax declaration-bundle case | 1: declaration_projection | C | let(field,field+1) encloses projection, including recursive binding and final return; nested projection balances before outer restoration. Existing defer already handles errors. |
| L79 | `src/macros.x:1093` _import xmacro branch | 2: diagnostics.emit, diagnostics.owner | C | Nested snapshot lets, owner outer/emitter inner, around borrow_diagnostics and remaining branch; preserve emit-then-owner restore before outer close_child. borrow_diagnostics shares diagnostics and conditionally installs child _emit_user policy; do not replace it with unconditional own_diagnostics. |

### Helper and false-positive audit

- `src/emit.x:828-842` _cleanup_barrier_enter/leave: all five caller regions
  are in the ledger. Four install both barriers, switch installs only break;
  deletion can remove both helpers and their paired-output convention.
- `Diagnostics.set_emitter` assigns emit and owner; both counted at speculation
  sites. Array resize and transaction rollback are not simple field restores.
- `Compiler.begin_lambda_captures` / end_lambda_captures change lambda_scopes;
  the two enclosing snapshots are counted, helpers themselves stay.
- `src/compiler.x:1735-1830` SymTxn begin/commit/rollback: cross-operation,
  conditional commit/rollback, not one lexical region. Rollback restores a whole
  SymScope plus eight scalar/handle fields and source-fact contents; commit
  merges staged maps into original identities. No field-by-field let migration.
- `lib/dispatch.x:23-39` render-path enter/leave: cross-operation caller-owned
  RenderPath stack, with cycle detection before installing path; preserve public
  helper contract. Current printers defer leave; do not inline path internals.
- `lib/lisp.x:92-112` Lisp.enter/leave and `1389-1400` machine slot
  acquire/release: persistent machine frames/freelist/depth across calls.
- `lib/error.x:394-407` _enter/_leave depth, Error.restore_landing/trim/restore,
  Context/Scope/pool push/pop, Match context tokens, exception landing and
  machine frame/undo records are nonlexical runtime protocols, not local lets.
- `src/statements.x:462` keyed alias restoration is included as rejected;
  absence versus prior Map value cannot be represented by capturing its address.
- `src/emit.x:946-958` generated C cleanup callback saves exit kind in emitted
  tokens, not x2c executing source. Keep emitted runtime protocol.
- Token locals in expressions.x:476 and parse.x:1036 only traverse a local
  cursor; no compiler state replacement. build.x:717, buffer.x:156, iterators,
  pool freelists, map backing swaps, Logger.set_global, and machine MW_CALL
  snapshots update/return state rather than restore a temporary value.
- `lib/list.x:1051` already uses $let for padding; baseline adoption is not a
  new candidate and is excluded from ledger counts.

### Proposed aggressive scope

Include every C region, including whole-function and snapshot forms. Include
all E regions as an explicit error-restoration expansion after targeted probes
show diagnostic recovery, state restoration, and returned ownership. Do not
claim E is exact equivalence. This is substantially broader than nine short
overrides. Keep R and the named cross-operation protocols out. Within E,
ParsedUnit.parse requires stating temporary-array cleanup on non-malformed
errors; CPP conditional work requires factoring without changing live-symbol
behavior. For six SDK globals, capture diagnostic message/notes and report
after decorators exit, preserving the existing early restoration. For paired
field restores, nest decorators in reverse restoration order to retain the
existing writes; symbol-pop, diagnostic replay, free and transaction operations
must retain their existing relative order. For thawed stack/privacy pairs,
evaluate thaw before installing privacy; thaw traverses/copies syntax and does
not replace either field. Plain installation order may reverse only with no
intervening call. Do not move effectful replacement evaluation across another
field installation.

Focused evidence to collect during approved execution: ordinary macro/lambda
fixtures, nested SDK failure reporting, malformed declaration recovery followed
by another declaration, source-map output and all loop/switch cleanup paths,
CPP live/default parity and retained declaration gensyms, nested Logger emission
and Lisp/Match lowering. Existing final agent-pr-check owns broad compiler and
self-host verification; no new recurring gate.

### Final defer cross-check

Cross-checked every src defer spelling against the parent manual ledger. Added
L78 (projection counter) and L79 (borrowed diagnostic callback state), omitted
by the initial state-name filters. Remaining src defers are already ledgered
state overrides, resource cleanup, symbol-scope operations, conditional
transaction rollback, or emitted/pattern AST rather than executing state.
Final C totals: 30 regions / 40 restored places; E: 30 / 52; R: 19 / 26.
Total lexical candidate ledger: 79 regions / 118 places. These totals include
both added regions; parent defer counts and lexical-region counts differ
because explicit restorations and multi-field regions are also represented.

## Complete Scope adoption inventory

Read-only survey at 8eb27f4bb2fad4d1ec179ed6fd9c1a3230b01a62.
Excluded generated lib/x2c.x. Searched all src/ and lib/ files for dotted
Scope operations, native Scope_* spellings, retain/release receiver calls,
existing $scope uses, and wrapper definitions/callers; inspected every region.
Counts below are lexical regions, not expanded macro call counts. No build or
production edits were performed.

### Counts

| Handwritten executable regions | src | lib | total |
| --- | ---: | ---: | ---: |
| retain/release | 0 | 0 | 0 |
| destination push/pop, including wrapper callers | 7 | 23 | 30 |
| compatible deferred replacement | 0 | 9 | 9 |
| nested template staging exclusion | 0 | 1 | 1 |
| changes Error/unwind behavior; separate decision | 7 | 5 | 12 |
| preserve conditional/cross-operation protocol | 0 | 8 | 8 |

Raw direct Scope.push call sites: src 7, lib 19. The lib total becomes 23
logical regions by counting the five callers of error.x _scope_push instead
of its one implementation. Scope method definitions are not caller sites.
The lisp.entry definition is one site, expanded by three callers. Expansion
counts would add two regions, but must not be reported as three edits.

Existing adoption: one retain region, lib/list.x:620; three destination
regions, lib/lisp.x:459,467,1668. These are not additional candidates.
Documentation-only executable examples in lib/scope.x: retain pairs at
486/489, 658/659, 904/907, and destination pair at 576/579 (three retain,
one destination). No executable handwritten retain/release remains.

### Compatible replacements (9, all lib)

| Site (push / pop) | Owner | Boundary and required preservation |
| --- | --- | --- |
| lib/lisp.x:424 / 427 | _scan_lisp_tokens | Declare tokenizer outside decorator; keep both creation and scan inside. |
| lib/lisp.x:901 / 902 | _call_lambda | Wrap only bindings allocation; existing outer defer Scope.destroy(frame) remains and runs after pop. |
| lib/lisp.x:1314 / 1315 | _auto_analyze | Wrap remaining preparation body, including managed builder; builder cleanup must precede pop. |
| lib/logger.x:545 / 547 | _memory_retain_value | Only clone_wide belongs in selected values scope; wide_values.push remains after pop. |
| lib/logger.x:637 / 639 | Logger.add_memory_sink | Wrap only backing Block creation; _new_sink remains after pop. |
| lib/match.x:1996 / 1997 | MatchCache.acquire | Keep precisely existing preparation block; fenced Error is raised after pop. |
| lib/match.x:2333 / 2334 | _capture_sites_initialize | Only Block creation; MatchCache.initialize remains after pop. |
| lib/match.x:2345 / 2346 | _capture_site_prepare | Plan creation and site-list insertion only; atomic publication stays after pop. |
| lib/pool.x:481 / 484 | Pool.retain_named | Existing failed-construction defer at 460-464 already pops before mutex destruction and Scope.destroy. Replace local push/map/pop by decorator and remove pushed flag/conditional rollback pop; preserve mutex_ready and finished guards and same unwind ordering. Declare Map table outside decorator to preserve subsequent assignments. |

Execution correction: `lib/lisp.x:442 / 443`, `$lisp.entry`, remains explicit.
Nested `$scope` evaluates the outer `$function` SDK expression before capture
substitution. Hoisting the destination still fails on the body splice. A
canonical-AST construction compiled but obscured the simple existing template;
it was discarded without changing compiler semantics. This corrects the
original ten-site compatibility estimate.

Typical direct change: `{ Scope.push(&frame); defer Scope.pop(); bindings =
%{}; }` becomes `$scope(&frame) { bindings = %{}; }`.
The decorator itself preserves one evaluation of destination; it pops rather
than destroys the Scope. Do not accidentally widen any listed region.

Pool is compatible but more involved than adjacent textual replacement:
`Map table; $scope(&pool.scope) { table = Map.new_capacity(capacity); }`.
This removes push/pop, pushed assignments, and the rollback conditional pop.
The decorator's defer is nested inside the existing construction rollback,
so it restores the slot before destroying mutex/storage on a transfer.

### Changes Error/unwind behavior (12)

These have plain pop, not deferred pop. A macro adds guaranteed restoration
on Error transfer; successful allocation destinations and lifetime can remain
identical. Treat this as an explicit behavior change, not exact equivalence.

| Site (push / pop) | Owner | Concrete boundary |
| --- | --- | --- |
| src/collect.x:187 / 190 | _header_cache | shutdown hook and header_contributions creation only |
| src/collect.x:347 / 349 | _flush_segment | overlay allocation only; declare overlay outside |
| src/collect.x:477 / 479 | _file | dependencies allocation only; declare outside |
| src/collect.x:510 / 512 | _file | generated.copy only; retained used afterward |
| src/collect.x:883 / 890 | header_symbols_open | artifact maps, optional reader, and its shutdown hook |
| src/collect.x:963 / 965 | _artifact_fetch | contributions map allocation only |
| src/collect.x:978 / 980 | _artifact_fetch | dependencies map allocation only |
| lib/error.x:281 / 284 | Error.initialize_raw | stack/policy creation; readiness and policies after pop. Startup failure reaches raw error floor, so no ordinary recoverable-unwind evidence. |
| lib/error.x:450 / 452 | _copy_value | wide clone in record-owned values Scope, returned after pop |
| lib/error.x:593 / 595 | _snapshot_value | wide clone in ancestor owner; keep ancestor traversal outside |
| lib/match.x:1860 / 1874 | MatchCache.new | full cache initialization. Adding pop does NOT destroy the new owner on failed construction; do not claim rollback repair. |
| lib/thread.x:125 / 155 | _run | callback Context, error capture, result export, work.close, then pool detach before pop. Runtime shutdown after pop. Outer new defer changes failures before/after existing try; preserve specialized result sealing and do not fold into routine batch. |

For collection maps, hoist only the result binding, not construction:
`Map overlay; $scope(&header_cache_scope) { overlay = %{}; }`.
Do not place parsing or later map population inside the region. Initial
Scope ownership stays cached, whereas ordinary immutable values still use
canonical pool ownership. No new retain region is implied.

### Preserve conditional and paired operations (8)

| Site | Owner | Why not direct $scope |
| --- | --- | --- |
| lib/context.x:127, rollback :122, normal close :364 | _open / Context.close | Scope stays active after _open returns and closes in a later operation. Rollback publication order includes Match, Error, pools, and Scope destruction. A decorator would pop on return and break Context. |
| lib/logger.x:452 / 455 | _emit_text | Conditional push avoids pushing already-current logger.storage; preserve conditional and appended-buffer rollback. |
| lib/logger.x:500 / 504 | Logger.add_text_sink | Same conditional destination; existing handed_off cleanup must remain correctly ordered. |
| lib/error.x:79 / 96 | x2c_error_catch_push | Conditional _scope_push; floor_only and catch-registration state surround construction. |
| lib/error.x:537 / 555 | _record_n | Conditional _scope_push, floor_only and record-region ownership; preserve manual protocol. |
| lib/error.x:739 / 743 | Error.policy_set | Conditional _scope_push and error-floor state. |
| lib/error.x:922 / 930 | _catch_retain | Conditional _scope_push and detached-record ownership. |
| lib/error.x:937 / 947 | _catch_commit_captures | Conditional _scope_push and borrowed record/capture lifecycle. |

_scope_push itself is lib/error.x:409-415: it returns zero when already in
state.scope, otherwise pushes and verifies the destination before returning
one. Five callers pair its result with conditional Scope.pop. Replacing it
with unconditional $scope changes stack depth/allocation/failure behavior;
there is no conditional decorator variant. Scope.push itself can grow its
stack and fail (lib/scope.x:594-610), so redundant pushes are observable.

### False matches, ownership operations, and implementation boundary

Scope.retain/release implementations are lib/scope.x:677/715 and push/pop
implementations :594/635. These implement the decorators' primitives and are
not adoption sites. Documentation references and examples remain useful when
teaching these primitives; do not count them as runtime code.

Pool.retain/release and String.pool_retain/release/detach are canonical-pool
ownership operations, not Scope retain/release: lib/pool.x:449,498,505,
554-555,572; lib/context.x:121,130,361; lib/error.x:426-427; lib/thread.x:111.
MatchLease.release in lib/match.x:2047 and callers :2106,2124,2143,2161,
2180,2198 releases cache leases, not a Scope. They cannot become $scope.
String.pool_retain/release (lib/string.x:147-159), List.pool_retain/release
(lib/list.x:137-152), and x2c_pool_values_retain/release declarations in
lib/common.x:242-243 are canonical-pool wrappers, also excluded.
x2c_scope_thread_release (declared lib/common.x:214) is whole-thread
teardown, not the paired lexical Scope.release operation.
Scope.new/destroy/cleanup manage independent Scope lifetimes; destination
$scope only restores the active slot and cannot replace their destruction.
No native Scope_retain/release/push/pop aliases or additional retain/push
wrappers were found. Other native aliases DO occur in macro templates and
compiler AST producers; their corrected census is below. Interpolated `$scope` AST variables in
src/literals.x are not decorator adoptions.

Recommendation: adopt the nine compatible regions with owner-specific review,
starting with the nine already-deferred sites; Pool follows as a bounded
rollback simplification. Present collection restoration separately as a
deliberate error-path improvement. Leave Error startup/capture and worker
sealing paths out of a convenience migration. There is no further executable
retain-region adoption to propose in src/lib.

### All other Scope operations

Second pass counted direct executable dotted call expressions in every
authored src/*.x and lib/*.x, stripping comments, string and character
literals, and subtracting method definitions and local forward declarations.
This is a lexical call-site census, not runtime frequency. Macro bodies count
once. Generated lib/x2c.x is excluded. Receiver-form Scope.cleanup's
`value.destroy()` is listed separately below. No reset/clear method exists.

| Operation | src calls | lib calls | Treatment |
| --- | ---: | ---: | --- |
| calloc | 31 | 9 | Allocation sites; preserve representation, zeroing, count and overflow checks. |
| malloc | 6 | 22 | Allocation sites; class only for independently reviewed fixed object construction. |
| realloc | 0 | 5 | Resizes existing owner allocation; no bracket replacement. |
| memdup | 0 | 0 | API definition/docs only. |
| malloc_in | 0 | 6 | Explicit destination allocation; already avoids changing active slot. |
| calloc_in | 0 | 3 | Explicit destination allocation; same. |
| memdup_in | 0 | 0 | API definition/docs only. |
| malloc_finalized | 0 | 0 | API definition/docs only; do not replace finalizers by lexical cleanup. |
| malloc_finalized_in | 0 | 0 | API definition/docs only. |
| free | 6 | 31 | Explicit per-allocation early reclamation, not region exit. |
| new | 0 | 2 | Context unnamed branch and runtime root initialization. |
| new_named | 0 | 13 | Independent named owner lifetimes, listed below. |
| destroy | 1 | 16 | Independent owner destruction, listed below. |
| move | 0 | 11 | Ownership transfer; not destination selection. |
| shutdown_hook | 3 | 4 | Process shutdown callbacks; not block cleanup. |
| initialize | 0 | 1 | Runtime initialization, not a lexical resource. |
| top | 0 | 11 | Current destination queries, identity checks and root installation. |
| owner | 0 | 4 | Allocation identity queries, not destination mutation. |
| name | 0 | 0 | API definition only. |
| stats | 1 | 1 | Observations; no bracket replacement. |
| cleanup | 0 | 0 | Protocol adapter definition only, calls value.destroy(). |
| push | 7 | 19 | Previous inventory; wrapper definition counts once here. |
| pop | 7 | 25 | Previous inventory, including rollback and paired-operation exits. |
| retain | 0 | 0 | No remaining direct executable calls. |
| release | 0 | 0 | No remaining direct executable calls. |

The nine _in allocation sites are lib/error.x:73,793; lib/pool.x:465,697,
747; lib/lisp.x:1391; lib/logger.x:265,490,631. Keep them direct: replacing
one allocation with push/defer-pop adds active-stack work and a new failure
point. Existing operations do not change the active slot (scope.x:770-824).
The five realloc sites are lib/block.x:111, lib/machine.x:395,435,
lib/match-machine.x:483, and lib/match.x:880. Growth preserves original
allocation ownership; $scope cannot replace that contract.

#### Independent owner creation and destruction

All 15 creation call expressions (2 unnamed, 13 named) and corresponding
destruction paths:

| Creation | Destruction | Decision |
| --- | --- | --- |
| lib/common.x:844 Scope.new | whole-runtime shutdown | Root slot initialization, no bracket. |
| lib/context.x:126 new_named / new | :123 rollback; :365 close | Context spans operations; preserve publication and dependency teardown. |
| lib/error.x:280 | :310 | Thread Error runtime; spans operations. |
| lib/error.x:436 | :429 | Error record region; survives construction and may detach with catches. |
| lib/pool.x:458 | :463 rollback; :519 release | Pool owns scope/mutex/table across operations. |
| lib/logger.x:636 | :612 | Memory sink values; sink lifetime, not add_memory_sink block. |
| lib/logger.x:662 | :682 | Logger storage lifetime; destroy after sinks/other teardown. |
| lib/match.x:1859 | :2084 | Cache lifetime; leases must end before disposal. |
| lib/match.x:2331 | :2235 | Process capture-site cache; shutdown lifetime. |
| lib/thread.x:124 | :113 | Result transferred from worker to joiner; neither worker block nor thread exit owns final destruction. |
| lib/lisp.x:456 | :457 rollback; :493 Lisp.destroy | Returned session ownership; keep conditional rollback. |
| lib/lisp.x:515 | :517 | Local token owner: possible $auto, but its existing destruction ends an inner block. Move its declaration inside that block to preserve exact boundary; keep Symbol status outside. |
| lib/lisp.x:898 | :899 | Local frame owner: strong $auto(Scope.new_named("Lisp frame")) candidate. Keep narrow $scope for bindings creation; do not retain a new ambient scope around evaluation. |
| lib/lisp.x:1602 | :1603 | Local token owner: strong $auto(Scope.new_named("Lisp tokens")) candidate; destructor remains at function exit. |

Additional destruction without explicit local Scope.new call:
src/collect.x:180 destroys header_cache_scope, created lazily through
destination allocation. Its process shutdown ownership stays unchanged.
Scope.cleanup in lib/scope.x:1006 calls value.destroy(); this is the existing
adapter that makes the three Lisp managed-Scope opportunities possible,
not another migration candidate. There are 17 dotted destruction calls plus
this one receiver-form adapter invocation.

The three local Lisp cases are the meaningful extra bracket opportunity
beyond push/pop. $auto owns the Scope independently; $scope only selects it.
For Lisp.read, preserve the inner boundary exactly:

```x2c
Symbol status;
{
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source + base, &tokens_scope);
  status = _read_tokenizer(tokenizer, source, base, cursor, out);
}
return status;
```

Do not replace named owners by `$scope()` merely because new/destroy look
paired. For example, Lisp frame allocations select that frame only while
creating bindings; later evaluation deliberately uses a different active
destination. $scope() around evaluation changes returned allocation lifetime.

#### Ownership transfers and process callbacks

All 11 direct move calls:

- lib/var.x:557, Var.move_wide: move a wide-value box to the requested owner.
- lib/context.x:104, Context.move_allocation: explicit custom-exporter move.
- lib/context.x:238,240 and :253,255: move container before recursive export
  and move it back only on failure. This deliberate identity change stops
  cyclic revisits. `$let` cannot replace moving allocation ownership, and
  unconditional deferred move-back would undo successful export.
- lib/block.x:309,310: move backing storage and control object together.
- lib/buffer.x:92: move Buffer object alongside its constituent Blocks.
- lib/pool.x:759: transfer surviving large allocation to ancestor owner.
- lib/lisp.x:1686: retain compiled function in the session owner.

All seven shutdown_hook calls: src/compiler.x:195 (_shutdown_lisp),
src/collect.x:188 (_cache_shutdown), :888 (_artifact_shutdown),
lib/context.x:66 (_shutdown), lib/pool.x:212 (_storage_shutdown),
lib/match.x:2313 (_shutdown), lib/thread.x:96 (_shutdown). Their callbacks
run once in reverse registration order at process shutdown while storage is
still available (scope.x:542-565). $auto/defer at registration would invoke
them too early. Keep these APIs and callbacks unchanged.

Top queries: lib/context.x:112,337 capture destinations; lib/error.x:411,413
implement conditional selector, :591 walks to the ancestor; lib/logger.x:
451,499 avoid redundant push, :660 captures owner; lib/thread.x:120 ensures
worker Scope state exists; lib/common.x:844 has two top calls to install an
initial root slot. Owner queries: lib/context.x:89,237,252 and lib/var.x:563
support export membership, rollback and wide-value identity. No direct
assignment to a current slot other than common.x's root initialization was
found. Stats calls src/main.x:111 and lib/scope.x:393 only inspect state.

#### Free and finalization boundary

The 37 direct Scope.free calls release raw allocations or form part of typed
destructors/rollback. `$auto(raw_pointer)` does not imply Scope.free: Cleanup
must be provided for that type. Preserve Buffer/Block/DisjointSet teardown,
conditional unsuccessful-construction frees, match/layout scratch, wide-box
cleanup and native mutex destruction. A class default free is not recursive.
The adjacent raw-array free/defer sites are candidates for a separate typed
cleanup design only if existing Cleanup semantics authorize them; inventing
a generic pointer cleanup to shorten them changes ownership assumptions.

malloc_finalized and malloc_finalized_in currently have no direct authored
src/lib callers. Their finalizers follow allocation moves/resizes and run on
free, zero-size realloc, owner destruction or shutdown (scope.x:745-764).
Lexical defer or class cleanup is not equivalent: it ends at a source block,
and generated class free is not a Scope finalizer. No new bracket facility is
needed for this unused-in-corpus API family.

#### Pool compatibility recheck

Pool.retain_named has three failure phases. Before Scope.push succeeds,
existing rollback destroys only initialized mutex/storage. After push succeeds
and during Map.new_capacity, existing rollback first pops, then destroys the
mutex and Scope. After the successful explicit pop, later initialization
stores plain fields and returns the pool. A narrow decorator around table
creation preserves these phases: failure entering $scope has no registered
pop, failure inside runs the inner pop before outer rollback, success pops
before later stores. Keep `mutex_ready` and `finished`; delete only `pushed`
state and its rollback branch. This is source-backed compatibility reasoning,
not a performed failure-injection test. Root should independently verify it.

### Correction: xmacro templates and native aliases

The preceding operation table is explicitly the .x dotted-call table, not
the complete src/lib corpus. The first pass omitted .xmacro templates and
native/AST spellings. The following supplement completes those surfaces;
counts are template sites once, never multiplied by instantiations.

| Operation | lib .xmacro dotted | lib .xmacro native | src AST producers |
| --- | ---: | ---: | ---: |
| malloc | 1 | 1 | 1 conditional alternative |
| memdup | 0 | 0 | 1 conditional alternative |
| free | 0 | 1 | 0 |
| top | 0 | 1 | 0 |
| move | 1 | 4 | 0 |
| new | 1 | 0 | 0 |
| destroy | 1 | 0 | 0 |
| malloc_in | 2 | 0 | 0 |
| shutdown_hook | 0 | 0 | 1 |

Totals: six dotted template sites and seven native template sites, all in
lib; two src AST-producer regions, with the allocator region selecting one
of two native names. No src .xmacro Scope calls. No native Scope_calloc
spelling was found in the current authored tree. Other operation counts are
unchanged. Full-corpus direct totals therefore include malloc src6/lib24,
free src6/lib32, top src0/lib12, move src0/lib16, new src0/lib3,
destroy src1/lib17, malloc_in src0/lib8; AST producers remain separate.

All additional sites and treatment:

- lib/autodiff.xmacro:34, $ad.dual generated boxing: Scope.malloc then copy
  the value and box it with the supplied tag. The allocation must survive
  return; no lexical cleanup. Class adoption would alter the selected tag,
  generated members and registration, so this is not a bracket opportunity.
- lib/map-generics.xmacro:47, $map._core_free: Scope_free follows both
  Bytes_free calls; preserve recursive backing-storage reclamation.
- lib/map-generics.xmacro:52-53, $map._core_new_capacity: Scope_malloc plus
  Scope_top captures the owning destination slot. Preserve the object and
  two backing arrays and their growth destination contract.
- lib/map-generics.xmacro:149-152, core growth: four Scope_move calls move
  staged hashes/entries control objects and backing allocations to map.scope
  only after reinsertion succeeds. Replacing with $scope changes allocation
  timing and rollback ownership; keep the staged transaction.
- lib/map-generics.xmacro:579-582, $map._core_compare in $map.core.observe:
  independent scratch Scope, deferred destroy, two malloc_in arrays. Strong
  additional $auto candidate: `Scope scratch = $auto(Scope.new());` removes
  the destroy statement. Keep both _in allocations; compare/qsort callbacks
  execute with the original active Scope, so `$scope()` around the routine
  would change callback allocation destinations. This is ONE template edit.
- lib/map-generics.xmacro:817, $map.export_context: move map to export
  destination before installing/moving backing storage. Keep transaction
  ordering and staged conditional cleanup; not a temporary destination.
- src/generate.x:108, _make_shutdown_registration: AST emits native
  Scope_shutdown_hook for unit shutdown. Preserve process lifetime and
  generated initialization order; a source decorator would not replace it.
- src/lambda.x:1122, _cell_declaration: selects Scope_memdup for initialized
  captured cells, Scope_malloc otherwise, then constructs one native call
  AST. Captured cells survive the defining block; no $auto or retained
  temporary scope. This is one allocation-producing region, two alternatives.

Native declarations/implementation/callback references are separate:
lib/common.x:161 declares Scope_shutdown_hook; lib/scope.x:983 implements
Scope_shutdown; lib/scope.x:171 registers Scope_shutdown with atexit.
They are not extra ordinary native calls, but the atexit registration is
another process-lifetime mutation that must remain. lib/error-private.xmacro
declares an ErrorRegion Scope field, and array-generics.xmacro:806 captures
Context.export_destination; neither calls a Scope operation.

The complete managed-independent-Scope shortlist is FOUR sites: three Lisp
sites above plus map-generics.xmacro:579-580. Retain/push inventory counts
remain unchanged because no additional retain/release/push/pop templates or
native aliases exist in these files.

## Additional macro-template exclusions

`lib/autodiff.xmacro:723-728` saves/restores `ad._loop-step` inside compile-time
Lisp using def/let*. This is not an addressable x2c runtime place; system $let
cannot replace it. Generic array/map old_* storage is transferred to a staged
object, not restored to the same location. RenderPath enter/leave remains a
separate recursion-path protocol. The complete xmacro pass adds no runtime
let regions to L01-L79.

## Class source sketches and consequences

ToolAction at src/toolchain.x:26,238 is the strongest optional candidate:

```x2c
class ToolAction struct {
  Symbol phase, List arguments, int verbose, dry_run, inherit_stdio, report;
} *;
ToolAction tool_action_new(
  Symbol phase, List arguments, int verbose, int dry_run) =>
  ToolAction.new(phase, arguments, verbose, dry_run, 0, 1);
```

The seven-statement allocation/assignment/return body becomes a forwarding
expression. The public four-argument wrapper stays. Scope.memdup copies one
flat record, whose borrowed List retains its canonical owner. Heap equality
and hash retain identity semantics. Generated new/free/cleanup, Var conversion
and printers are additive public API. Registration is eager: the generated
Var adoption in etc/builtin-macros.xlisp:480-485 reaches initializer emission
in src/protocol.x:2070-2078 and tagged reservation in lib/dispatch.x:187-194,
451. lib/var.x:240-250 enforces 32 custom rows. An unused box still costs a
row when its owning unit initializes. No recursive free or Scope finalizer.

AdTape at lib/autodiff.x:18,32,43 could use:

```x2c
class AdTape;
// Keep AdNode's definition and explicit <adnode> converters here.
class AdTape struct { Array nodes; } *;
void AdTape.init(AdTape tape) { tape.nodes = %[]; }
```

Its Array field requires explicit init, not generated init. This saves little
and adds public methods/registration; generated free leaves the Array, nodes
and closures to their Scope. Compiler's owner-dependent sharing and Lisp
registration cannot be replaced; Emitter is stack-backed (src/emit.x:1897).
GenNames and ProjectTarget/Profile would merely relocate initialization into
new methods. Preserve custom allocation/destruction in Buffer, Context, Func,
Pool, Mutex and DisjointSet. Class adoption remains a separate decision.

## Executed probe evidence and limits

The earlier baseline build, focused 188-test/1589-assertion run, and
/tmp/x2c-adoption-probe.x remain valid evidence for this unchanged baseline.
They are not migration validation. The temporary class probe confirmed all
ToolAction-shaped fields, borrowed List identity, canonical List survival,
swapped Array cleanup, Scope allocation balance, generated Scope.memdup and
eager tagged initialization without boxing.

Expanded probe: /tmp/x2c-adoption-expanded/map-generics.xmacro is a copy with
only the two staged Bytes initializers and comparison Scope initializer changed
to auto. /tmp/x2c-adoption-expanded/maps.x embeds the current typed-map provider
and imports that temporary macro. It compiled and ran, exercising 2,000 keys,
multiple grows, retrieval, equal/unequal compare, and unchanged live-allocation
count after both maps are freed. Output: generic map managed cleanup probe
passed. Build log: debug/adoption-expanded-maps.log.

The initial probe packaging used an absolute .x include, producing a missing
absolute typed-map.h at native compile. Embedding the provider in the temporary
unit resolved this packaging issue; no repository change was needed. Do not
present that setup failure as a migration defect or omit it from probe history.
No allocation failure was injected. Pool rollback equivalence and large let
regions are source-reviewed; implementation still needs their focused existing
coverage and final publication gate.
