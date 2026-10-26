# Repository consistency repairs from the October 26 review

> Status: done. R1-R12 and Q1 implemented and validated on 2026-10-26.
> Implementation through `12705c82e`; the final delivery also closes this plan.
> Baseline: `4ea1067462a37e4c1db0d18b3f2d18cd70b0210f`.
> Covers findings R1-R12 and the qsort contract conflict Q1.
> Gary selected consistent search names, retained libc with a qsort callback
> exception, and selected one operator-fact table. Gary accepted `find(predicate)`,
> `index(value)`, the source/ABI break, and no compatibility aliases.
> The full publication gate passed. The subsequent installer repair below
> resolves the original clean-installation verification limit.

## Result and scope

Repair the reproduced reader, initializer, and package-bundle failures.
Correct examples, ownership contracts, and implementation navigation.
Make the bounded emitter path easier to follow. Consolidate collection search
names and operator facts. Keep libc sorting and state its callback exception.

Keep macro-visible canonical AST forms, Thread result ownership, Pool
lifetimes, and Torch storage behavior. Preserve runtime signatures except
for the explicitly proposed search migration in D1.
Change authoritative sources and regenerate their derived artifacts through
existing targets. This plan adds no recurring gate or publication step.

The earlier [language-reference writing plan](../review-remediation-2026-10-11.md)
retains its separate scope. This plan owns only the October 26 findings.

## Evidence at the baseline

The read-only review built a current compiler in an isolated `/tmp` snapshot.
All 1,047 unit tests passed, with 27,270 assertions. The documentation audit,
77 selected tooling tests, and seven independent site tests also passed.
These results did not cover the failures below. No sorting performance or
installed-libc leak measurement was made.

| Finding | Verified observation |
| --- | --- |
| R1 | 2,000 nested parentheses raise `size-limit`; 200,000 reader prefixes followed by `x` terminate with SIGSEGV. |
| R2 | A record with `char text[2]; Var number;` and initializer `{'a','b',7}` generates `'a', char_var('b'), 7` and fails native compilation. Explicit inner braces succeed. |
| R3 | A package built through `packages/package.mk` fails bundling on a missing legacy `.link` file. Supplying that empty file exposes a second `void-op` failure. |
| R4 | Reused storage makes the String example print `abcdevv 0 len=7`. Adding the missing terminator produces `abcde 1 len=5`. |
| R5 | Against pinned libtorch 2.10.0, source mutation reaches a `select` view but leaves `index_select`, `masked_select`, `cat`, and `stack` results unchanged. |
| R6 | Pool comments promise survivor copying by Thread join; current join returns result bits without ownership transfer. |
| R7 | The documented compiler glob selects 29 of 62 units and fails on missing generated compiler headers. |
| R8 | The same predicate argument compiles without warnings; `List.find` returns `20` and `Array.find` returns `-1`. |
| R9 | The organization guide names 19 former top-level compiler entry paths whose entries now live inside module directories. |
| R10 | Architecture and operator prose assign operations to owners that differ from current source and other documentation. |
| R11 | Declaration emission forwards complete nodes, reconstructs a head, and then discards that head before emitting its fields. |
| R12 | Compiler and component code contain separate compound-operator tables. Their current mappings agree. |
| Q1 | ER-8 conflicts with libc-backed comparison paths. Gary selected a documented exception; no libc defect or installed-libc leak was demonstrated. |

Temporary review artifacts are useful supporting evidence, but implementation
must reproduce these observations from source. Their `/tmp` paths are not
dependencies of this plan.

## Selected directions

### D1. Use `index(value)` and `find(predicate)`

Owners: [Array operations](../../lib/array/generics.x),
[List transformations](../../lib/list/transformations.x),
[List indexing](../../lib/list/traversal.x), and [Iter](../../lib/iter.x).

Gary approved these two operations on 2026-10-26:

| Operation | Families | Result | Absence |
| --- | --- | --- | --- |
| `index(value)` | Array and List, including their typed families | First zero-based `int` position equal to `value` | `-1` |
| `find(predicate)` | Array, List, and Iter, including typed sequence views | First accepted element as `Var` | `void` |

List already has both names with these meanings; Iter already has `find`.
Bring Array into that convention. Keep each family's existing equality policy
and integer index domain. A null or empty sequence has no match. Predicate
acceptance uses ordinary Var truth. A null predicate has no match.

Every `find` returns Var, including a typed collection's method. This gives
absence one spelling without treating zero, false, or NULL as missing.
Callers test `result is void`. A returned element retains its existing
ownership; searching neither copies nor transfers its storage.

Array and List search leave their inputs unchanged. Iter search consumes
through the match and leaves the cursor immediately after it. Failure to
find a match exhausts the iterator; a null predicate consumes nothing.
The predicate is borrowed and synchronous. Source and callback Errors
propagate through the existing iterator implementation.

Rename Array's existing value scan to `index`. Keep `List.index`, `List.find`,
and `Iter.find` unchanged. Implement Array predicate search through its existing
iterator and `Iter.find`; generated Array families reuse their iterator/boxing
owner. Keep native equality lookup native in packed Arrays.

Use one direct migration, without compatibility aliases:

| Existing call | Consolidated call |
| --- | --- |
| `Array.find(value)` and typed-family equivalents | `index(value)` |
| `Array.indexof(value)` and typed-family equivalents | `index(value)` |
| `List.find(predicate)`, `Iter.find(predicate)` | Unchanged |

This repurposes `Array.find` from value-to-index to predicate-to-element.
Its generated native signature changes. Removing `Array.indexof` also removes
native symbols. Existing native consumers must rebuild; existing value-search
callers must migrate to `index`, including searches for Func values.

Gary accepted this source/ABI break on 2026-10-26. Remove duplicate names
without forwarding wrappers.

Update the existing Lisp callback adapters/target rows affected by Array's
new predicate signature. Existing List and Iter adapters need no rename.
Preserve Lisp language spellings. Migrate calls by resolved receiver and
binding; unrelated String, SymbolSet, graph, and application methods stay as is.

### D2. Keep libc and document the qsort callback exception

Owners: [Array sorting](../../lib/array/array.x),
[Map comparison](../../lib/map/generics.x),
[List sorting](../../lib/list/transformations.x),
[Var comparison](../../lib/dispatch.x), and
[ER-8](../../agents/x2c-code-standard.md#errors).

Gary selected the exception on 2026-10-26. Keep the existing libc calls and
sorting algorithms. The review established a documentation conflict; it did
not demonstrate a libc defect that calls for a replacement algorithm.

State the exception at ER-8 and link affected API contracts to it:

> Comparisons invoked by libc qsort must return normally. If an Error or
> other nonlocal exit crosses qsort, cleanup, memory safety, and container
> state are not guaranteed.

Apply that statement to `Array.sort`, comparisons of `Array.sort_by` keys,
and Map's comparisons inside qsort, including generated Map families.
`List.sort` and `List.sort_by` delegate to the affected Array operations.
Keep successful ordering, stability where promised, and return values.

Distinguish `sort_by`'s two callbacks: its key extractor runs before qsort,
so its existing Error and failure-atomicity contract remains. Comparing the
extracted keys happens inside qsort and has the exception above.
`Array.sort_with` already sorts in x2c; its existing callback Error,
cleanup, and failure-atomicity contracts remain unchanged.
Map's final lexicographic comparison runs after qsort; its ordinary Error
behavior also remains unchanged.

This is a contract correction. It adds no sorting implementation, callback
bridge, Error capture state, allocation, lock, benchmark, or new test that
claims unsupported qsort unwinding is safe.

### D3. Consolidate operator facts in the existing private meta owner

Owners: [operator ledger](../../src/operator-ledger.x),
[dynamic operators](../../src/components/dynamic-operators.x),
[compiler meta operations](../../lib/compiler-meta.x),
[prelude collection](../../src/collect/walk.x), and
[installed payload](../../etc/x2c-payload.x).

Gary selected one table. Recommend placing the existing 22 operator rows in
`lib/compiler-meta.x`, exposed by the ordinary internal, nonstatic meta function
`meta List _x2c_operator_rows(void)`. This module already ships with the
compiler and supplies its private meta support.

Keep each row's operator, precedence, compound spelling, protocol member,
and derived-comparison flag unchanged. Keep existing `Symbol.*` signatures
and compiler-state operations in `operator-ledger.x`; their case projections
read the shared rows. The component's private lookup reads the same rows,
skipping rows with no compound spelling and returning the binary column.
Delete both the old compiler-local table and the component's ten-row copy.

This extends the private meta module to include pure compiler facts beside
its compiler-operation prototypes. It adds one internal symbol and updates
the module header, library-manifest description, and generated catalog.
It adds no source unit or payload entry. Include `compiler-meta.x` explicitly
from consumers that need it, including `dynamic-operators.x`; `rewrite.x`
currently includes only the public `meta.x` owner. The function belongs to
compiler support, with no public SDK query or helper RPC.

A temporary provider/consumer probe established ordinary meta sharing. The
integrated change must also pass installed-prelude and project-helper checks.
Use the existing generators and performance process for the authored compiler
change. A shared linear lookup needs no new registry or cache.

## Repair specification and acceptance

### R1. Fence reader-prefix recursion

Change [datum-reader.x](../../lib/datum-reader.x) so the existing depth fence
covers each recursive descent through Lists and reader prefixes. Give the
policy one owner. Preserve the existing List threshold, `size-limit` cause,
operation detail, cursor behavior, and incomplete-input handling.

Extend the existing Lisp depth test with quote, quasiquote, unquote,
unquote-splicing, and mixed List/prefix nesting. Check the limit boundary,
ordinary forms, and recovery after a caught limit. A bounded subprocess
reproduction must receive the cause instead of SIGSEGV. No recursion engine
or new public limit is needed.

### R2. Recognize string literals exactly in initializers

Repair both recognizers in
[initializer subobjects](../../src/initializers/subobjects.x). Preserve source
literal recognition and destination-array checks. Capture the literal's type
and use the existing `Type.is_char_pointer_like` query, following the nearby
working conversion owner. Add no second validator or origin tracking for
constructed ASTs.

Check the flat `char[2]` plus Var reproduction, its explicitly braced control,
genuine string initializers, and a symbolic-bound case. Extend the existing
initializer fixtures so both ordinary and symbolic layout paths are covered.
The program must print both characters and integer seven without C warnings.

### R3. Complete the bundle path without a dependency manifest

Update [bundle](../../packages/tools/bundle) to inspect `.native.rsp`, preserving
the requirement for distribution data when native inputs need it. An empty
response requires no legacy `.link` file and no dummy manifest.

Omit dependency metadata that does not exist. Keep compiler, runtime,
archive, platform, and package identity fields. Existing package listing
treats an absent dependency version as unavailable; the index generator
already supplies its version fallback. Preserve manifest-backed metadata
and argument order. Do not silently discard nonempty native response data.

Use inert pure-x2c and mixed C/x2c packages through the real shared Makefile.
Bundle, install into a scratch prefix, and run an importing consumer. Cover
the nonempty-response refusal and one manifest-backed control using prepared
inputs. Put regressions in the existing package test harness; require no
network preparation or new matrix entry.

### R4. Correct String finalization instructions

Write the terminating NUL in the source example in
[String storage](../../lib/string/storage.x). Preserve the uninitialized-buffer
contract of `String.malloc`. Regenerate the String reference and derived text.
Run the corrected example once with reused storage and verify `abcde 1`.
Do not add allocator initialization or another required output-sample run.

### R5. State Torch view and copy behavior

Correct [Torch source commentary](../../packages/torch/src/torch.x) and the
[Torch guide](../../docs/src/guide/torch.md). Separate views, allocating results,
and layout-dependent operations such as `reshape` and `flatten`.
Keep native wrapper behavior and handle ownership unchanged.

Verify the explanation against the pinned libtorch contract and the existing
mutation probe. Use cached dependencies for focused execution; no fresh
dependency installation is needed solely to edit this prose.

### R6. Correct Pool and Thread ownership explanations

Update the [Pool header](../../lib/pool/pool.x) and
[Pool.detach documentation](../../lib/pool/threads.x). Explain the shared
process root, thread-active child pools, and caller ownership of detached
pools. Remove the claim that Thread join copies successful survivors.
Use [the current Thread contract](../../lib/thread.x) and
[the lifetime guide](../../docs/src/guide/contexts-and-threads.md) as the premises.

Regenerate the Pool reference and derived text. Cross-check the explanations
against worker initialization, detach, release, and join. No new result walk,
copy, export, lock, or ownership obligation is part of this repair.

### R7. Publish a working extension-compiler recipe

Replace the stale `src/*.x` recipe in
[the package guide](../../docs/src/guide/packages.md) with the unit enumeration
and include directories used by
[the native-module probe](../../unittest/probes/run-native-modules.sh).
Use `tools/sources.sh`; do not copy the current count into build logic.
Specify the shell needed by the published command.

Execute the command as written with an inert tally extension. Prove the
resulting compiler translates a consumer when the package module is absent
or stale, as the existing probe does. Reuse that example and its build
boundary; add no new public build mode or compiler-build wrapper.

### R8. Consolidate sequence search names

Implement the approved D1 names in the existing Array family generators. Rename Array's value search to
`index`, remove its redundant `indexof`, and make `find` predicate search.
Keep the native Array scan. Reuse `Iter.find` for predicate search and leave
existing List and Iter names and implementations unchanged.

Update affected Lisp callback target rows through their existing adapters.
Migrate first-party calls by binding and receiver, and
update [the collections guide](../../docs/src/guide/collections.md),
[the iteration guide](../../docs/src/guide/iteration.md), API comments, examples,
and the migration documentation for the removed signatures. Keep unrelated
methods and Lisp language spellings unchanged. Add no forwarding aliases.

Extend the existing Array, List, and Iter suites to check first match,
absence, matching zero/false/NULL values, predicate truth, and iterator
position after search. Cover typed-family boxing and native index lookup.
Preserve Func-value equality lookup through `index`. The current confusing
predicate example must use `find` and return the same element
for Array and List. Searching must preserve the element's lifetime and leave
Array/List input storage unchanged.

### R9. Repair module navigation

Correct the 19 former entry paths in
[the organization guide](../../agents/x2c-code-organization-guide.md), using
[the source README](../../src/README.md) and `tools/sources.sh` as references.
Distinguish entry units, nested members, and independent components.
Check the corresponding runtime names while editing that map.

Update [the site README](../../site/README.md) to describe the statistics tool's
recursive source inventory. This is part of the source-layout explanation;
the statistics algorithm does not change. Verify every edited path directly,
because the current path audit does not interpret all relative filename lists.

### R10. Correct implementation-owner descriptions

Update [architecture](../../docs/src/internals/architecture.md) so the narrative
and ownership table agree: main dispatches; translation coordinates inputs
and writes depfiles through deps. Update
[the operator reference](../../docs/src/reference/language.md) to distinguish
expression/protocol resolution, Var comparison lowering, and dynamic fallback.

Trace the edited descriptions to their named functions. Reuse the String-add
and Var-comparison AST/output probe. Preserve all operator semantics.

### R11. Narrow declaration emission helpers

In [emitter dispatch](../../src/emit/dispatch.x), match the complete `declare`,
`decl`, `bind`, `param`, and `function` productions. Pass their named captures
to [declaration emission](../../src/emit/declarations.x). Remove `_declare_stmt`
and `_decl_stmt`; keep the statement semicolon at its recognized production.
Destructure the trusted `Type.declaration_ast` result at the other caller.

Preserve type-before-binding emission, List-rest parameter spelling,
defer-owner lookup, function-name restoration, and the `static_objects`
lifetime. Leave typedefs, aggregates, native aliases, initializers, and
fallback C emission with their existing owners. Introduce no new AST form.

Compare generated C/H bytes for representative declarations and run the
existing declaration, native-alias, static-local, and relevant stack-budget
fixtures. A mechanical cleanup must not require accepting unrelated fixture
changes. Keep this diff separate from R2 while reviewing it.

### R12. Resolve the operator-table duplication

Apply D3: move the rows unchanged and preserve precedence, direct/derived
protocol, and compound-assignment results.
Keep the component's lookup private and avoid introducing runtime work where
the compiler currently projects constants.

Check all ten compound operators through native and Var update paths and
compare representative generated C/H. Prove cold prelude collection, linked
meta use, an ordinary project meta helper, and a scratch installed compiler
can resolve the shared owner. Confirm the existing payload includes it and
the source-unit inventory remains unchanged. Ensure generated user C needs
no compiler-only headers or linkage. Completion requires one table and both
consumers reading it.

### Q1. Document the selected libc exception

Update ER-8 and the authoritative Array/Map comparison comments with D2's
exception. Link `List.sort`, `List.sort_by`, and affected generated-family
descriptions to that contract. Regenerate API documentation and derived text.

Remove claims of safe Error propagation or failure atomicity specifically
for a comparison that exits through qsort. Preserve `sort_by`'s key-extraction
guarantee and all existing `sort_with` guarantees. Review the wording against
the actual callback locations. Existing successful-sort and supported-error
tests retain their expectations. Sorting code and libc usage stay unchanged.

## Implementation order and delivery

Gary authorized the full plan on 2026-10-26. Implement in this order:

1. Reproduce R1-R3 on the then-current tree and extend their existing tests.
   Repair these independent failures first.
2. Correct R4-R7, R9, R10, and Q1 at their authoritative sources.
   Regenerate derived documentation together.
3. Complete the bounded R11 emitter cleanup, reviewing output equivalence
   independently of the initializer repair.
4. Implement R8's approved public contract and R12's shared
   table. Preserve installed-compiler behavior. Use the existing performance
   process for applicable compiler/runtime changes.
5. Regenerate remaining bootstrap, linked-meta, runtime aggregator, and
   documentation outputs through their existing owners as applicable.
6. Review the complete authored diff and generated changes. Fix findings from
   that review before publication validation.

These are coherent work groups, not a requirement for one commit or PR per
finding. Use the root delivery rules and the mode Gary selects for the later
implementation. Delivery follows the root direct-publication instructions.

For publication, integrate current `origin/dev`, preserve unrelated work,
and ensure `tools/gate-state.py ensure agent-pr-check` for a code batch, or
`doc-check` for a documentation-only batch. Let that command own its broad
components. Run the existing performance checkpoint for applicable authored
compiler/runtime changes. Do not repeat unchanged evidence or expand gates.

Complete a finding only when its acceptance evidence is recorded. R8 delivers
two consistent names through the agreed migration. R12 delivers one table.
Q1 corrects the contract while preserving libc sorting. Record remaining work
and update this plan as batches land.

## Adversarial review

A separate agent, capped at medium reasoning, source-reviewed all R1-R12 and
Q1. It rejected the proposed extra search name and compatibility wrappers
because they retained conflicting meanings while adding API surface. D1/R8
recommended existing `index` and `find` conventions with an explicit
source/ABI decision. Gary then accepted both names and the break. The remaining recommendations passed that source review.
R11 is a readability change, not a demonstrated defect. R12 required integrated verification. The agent ran no builds or runtime
reproductions. Its subsequent review of the authored implementation found no
actionable defects across all 13 items.

## Implementation evidence

All 13 repairs are implemented. No compatibility aliases or replacement
sorting algorithm were added. Existing generators refreshed the runtime API,
linked meta code, bootstrap, module catalog, and book.

- R1/R8: the combined Array, typed-Array, List, Iter, and Lisp suites passed
  197 tests and 6,538 assertions. The 200,000-prefix case raises `size-limit`.
  Ordinary and typed Array predicate search also passed a compile-time probe.
- R2: flat, braced, and string character-array initializers pass the ordinal
  and symbolic fixtures. The flat reproduction now prints `ab 7`.
- R3: pure-x2c and mixed C/x2c bundles build through the shared Makefile,
  install, and run importing consumers. Native-input refusal and a prepared
  manifest-backed control pass in the existing package-install probe.
- R4-R7/R9/R10: the corrected String sample passed with reused storage;
  pinned Torch mutation/layout probes passed; Pool/Thread prose follows the
  ownership source. The exact extension recipe built a compiler that handles
  absent and stale modules. Edited source paths and implementation owners
  were checked directly.
- R11: 14 representative C/H artifacts were byte-identical before and after
  the emitter cleanup. Existing declaration and stack fixtures pass.
- R12: one authored 22-row table serves both consumers. All ten native/Var
  compound operations, project-helper use, and prepared installed-prefix
  warm/cold translation passed. Source-unit inventory is unchanged.
- Q1: only the contract prose changed. Key extraction, `sort_with`, and Map's
  final comparisons retain their existing Error behavior.

`tools/gate-state.py ensure agent-pr-check` passed on the integrated code:
1,049 unit tests with 27,366 assertions; 1,294 compiler fixtures with 2,859
artifacts; documentation audit; 122 compiled output examples; command checks;
bootstrap/stage comparisons; and cold collection. The first attempt exposed
only two old Array symbol snapshots, which were regenerated and reviewed.

The performance checkpoint used three alternating runs per tree of seven
byte-identical translation inputs with matching prelude interfaces. Median
retired instructions were 30,967,765,150 on `01491d642` and 31,027,800,100 on
`91ff5996`, a 0.19% increase. Median elapsed time was 1.89 and 1.90 seconds.
Later test-expectation and prose changes do not change that measured code.

At initial completion, `make install` failed on the baseline and candidate
while writing interfaces because `x2c_ident` was unresolved. The staged payload also
omits nested runtime sources needed by an ordinary project meta helper.
R12's installed-prefix check used the existing package-probe staging method:
matching interfaces and all runtime source directories. It passed without a
checkout dependency. This verifies the shared owner in a prepared prefix;
at that point it did not establish that the unchanged installer worked.

## Installer follow-up

Gary requested repair and clean installation on 2026-10-26. The installer
omitted the split `array`, `func`, `map`, and `lisp-targets` source directories.
That incomplete payload caused both interface generation's unresolved
`x2c_ident` and the installed project-helper failures. The repair replaces
the directory list with a recursive runtime-source copy. Interface generation
is unchanged.

A fresh `make install PREFIX=...` now succeeds. Both installed source trees
contain all 128 runtime source files. The package-install probe uses the real
installer instead of manually copying runtime sources and checkout interfaces.
Its installed project helper, imports, and warm/cold C/H comparisons pass.
The shared-row project helper and all ten native/Var compound updates also
pass from the clean prefix, returning `22 11 11`. The release-bundle installer
test passes, including relocation, package use, reinstall, and checksum refusal.
No source or interface files are added after installation.

## Plan review

The parser and binder establish the canonical typed forms that R2 and R11
consume. Those consumers add no shape or origin validation. Thread and Pool
establish ownership at their existing boundaries; R6 changes explanations.
The package build produces the native response file, and bundling owns its
distribution contract; R3 reads that format without reconstructing it.

The design reuses the reader fence, Type queries, package metadata readers,
AST patterns, generators, and existing tests. R8 gives existing scans canonical
names and removes redundant spellings; its approved migration changes ABI.
R11 removes two internal forwarders and redundant node reconstruction.
R12's one private meta function
shares operator facts through an existing shipped owner and removes two table
definitions. Q1 adds prose only. The repair uses existing x2c forms and
operations without another IR, sorting algorithm, validation layer, callback
framework, cache, registry, or process lock.

R1 extends the existing depth check to the recursive path that can exhaust
the stack. Its rejection tests protect the existing size-limit behavior.
R3 preserves the existing refusal of native inputs without distribution
data; its rejection case protects complete native linking. R2's fixtures
exercise valid character and string initializers. R8's tests establish search
results, absence, and migrated call contracts. Q1 adds no test for unsupported
nonlocal exits through qsort. No new validator or dedicated diagnostic is
proposed. Routine prose and navigation repairs need no new rejection tests.

D1 records the approved names and return contracts for Gary's selected
API consolidation. D2 records his libc exception. D3 records his single-table
choice and the approved private owner. Gary authorized implementation of the
full plan on 2026-10-26. Broader changes require a new discussion of affected
paths and costs before implementation.
