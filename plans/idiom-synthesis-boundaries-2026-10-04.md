> Status: reference
> Research snapshot, 2026-10-04, against origin/dev
> 4107b60af83a67abb4ceb058d4d327ce13e36ce7; original baseline 272ba77c.
> Gary subsequently authorized private implementation. The main synthesis
> owns the current dev refresh, binder decision, changes, and verification.
> Historical statements below describe the investigation before implementation.
> Publication and a PR remain held for Gary.

# Compose idioms while preserving runtime boundaries

## Result and recommendation

Use one convention per role, not one spelling for every pointer or callable.
Keep published pointer signatures and the five Macro native identifiers.
References should express private synchronous output borrows. `$scope`
should express a complete lexical destination bracket. Retain direct Scope
operations when the owner persists across calls or restores several subsystems.

The strongest bounded implementation is private output adoption in Match and
the Lisp reader. A second bounded change can replace the ordinary lexical
brackets in MatchCache construction and meta-group reset. Neither requires a
new runtime abstraction, public adapter, diagnostic, registry, or gate.

This plan does not authorize implementation. It does not promise line savings
from changing punctuation alone. The main benefit is consistent caller syntax
and visible lifetime boundaries, measured separately from source line counts.

## Evidence and scope

### Refresh against dev 4107b60a

The 2026-10-04 refresh compared every changed `lib/` and `src/` owner with
the original `272ba77c3` survey. The recommendations remain four private
reference migrations and two lexical Scope substitutions. Their function
bodies, public output contracts, and underlying cleanup operation are unchanged.
The meta-group bracket moved to 815-817; it still surrounds one reset call.

- `0b721a6c` expands Macro scalar-list application and typed quotation holes.
  `Macro_apply` keeps its name and signature. `_macro_items` at
  `lib/macro-value.x:95-103` distinguishes whole argument sequences from
  identifier, quotation, and pending-template records. `Macro.declared` at
  126-129 and `Macro.inserted_items` at 134 add ordinary dotted helpers.
  Retain the five native identifiers and these scalar-lifting contracts;
  a naming cleanup must not reinterpret a List as one argument.
- `macro-quotation-scalar-splice.x` and `macro-quotation-typed-values.x`
  exercise these new application and declaration shapes. Their source and
  checked-in expectations were inspected; they were not executed here.
- `182d0175` and selector-helper changes add private linked meta helpers in
  `src/linked-meta.x`. Their exact strings in `linked_meta_targets` connect
  imported definitions to linked native functions. This reinforces preserving
  native registration identities without adding dotted forwarding families.
- `e83477ef` makes emitted copies of a public `meta` function weak through
  `src/compiler.x:1642-1652`. Static definitions remain static. Equal C
  spelling still does not prove equal method facts or source reflection.
  Do not change this linkage policy as part of runtime naming.
- `a16d74e2` installs collected meta stubs before file-scope constant calls.
  The stub receives an explicit canonical Type at
  `src/meta-native.x:83-93`. The native reference-marker normalization and
  `Compiler.func_signature` contracts remain intact. Public pointer outputs
  still cannot become source references without a compatibility decision.
- `a0beb529` and `549c9c68` publish public object declarations after function
  or static definitions and align header qualifiers with runtime initializer
  lowering. `Partition.object_header` at `src/generate.x:450-458` owns that
  rule. The proposed private migrations do not move objects across visibility
  boundaries. Preserve the new ordering and qualifier behavior, covered by
  existing `header-object-after-function` fixture source and expectations.
- `ef8bfbf1` replaces Pool's intern Map with key-only `PoolTable`. Its new
  `PoolTable._setdefault` already takes a required `int &inserted` at
  `lib/pool.x:94-97`, consistent with the recommended private borrow role.
  It retains `$scope(&pool.scope)` at 845-846. No Pool representation change
  belongs to this plan; runtime Scope call counts remain unchanged.

The refreshed runtime corpus has 63 files and 30,928 physical lines, compared
with 30,938 at the original survey. `macro-value.x` grew from 809 to 834 lines.
All line references below now describe `4107b60a`. This is refreshed source,
history, fixture, and documentation evidence, not new build or execution proof.

### Survey method

The survey searched all hand-authored top-level `.x` files in `lib/` and
`src/`, excluding generated `lib/x2c.x`. The runtime corpus contains 63 files
and 30,928 physical lines. Searches covered full multiline signatures,
reference declarations, scalar/handle pointer parameters, Scope calls, native
Macro identifiers, and their compiler consumers. Related `.xmacro`, `.xlisp`,
tests, book contracts, active plans, and selected history were inspected.

This is a role census, not a proof that every pointer in arbitrary C callback
syntax is an output. Array pointers, callback state, retained addresses, and
native boundary declarations were examined as exceptions. No external clients
were surveyed. No build or runtime test was performed for the plan refresh.
The implementation checks below
resolve the remaining translation and exception-path questions.

References were compared with the current style guide at 938-989, organization
guide at 50-69, language reference at 481-513, and the idioms chapter. Private
local-record `Record.step(Record &r)` names are explicitly allowed. For example,
`Parser.flags`, `Format.conversion`, and `Script.trim` are not naming defects.

## Comparison matrix

| Role | Current examples | Settled convention | Disposition |
| --- | --- | --- | --- |
| Ordinary public operation | `Macro.binder`, `String.try_next` | `Type.method` | Keep and use for new ordinary operations. |
| Compiler-native intrinsic callable | `Macro_apply`, `Macro_case_capture_at` | Stable exact native identifier | Retain all five Macro names and their current public signatures. |
| Private operation context | `Parser.flags(Parser &)`, `Option._read_row(Option &)` | Value record, reference receiver; local-record steps may omit `_` | Keep both spellings according to current style exceptions. |
| Private required scalar output | Match `_first`, `_replace`, reader cursor | `T &` | Convert only after caller-requiredness is traced. |
| Private optional scalar output | Reader result | `T &?` | Convert without eliminating absent-output behavior; retain the scanner pointer family. |
| Published pointer output | `String.try_long`, `Symbol.try_new`, scanner APIs | Preserve the published declaration and reflected type | Retain; no parallel reference wrapper. |
| Native pull callback | `IterNextFn`, `_next` families | Pointer output with existing C callback signature | Retain. |
| Retained mutable slot | `Scope.push`, Logger memory destination | Pointer | Retain because the address outlives the call. |
| Array or row storage | worker pids, cache seen table, typed-map callbacks | Pointer | Retain. |
| Ordinary lexical destination selection | MatchCache construction, meta-group reset | `$scope(pointer)` | Bounded adoption candidate. |
| Cross-call destination selection | `Context.open`/`close` | Explicit push/pop owned by lifecycle | Retain. |
| Error-floor and conditional destination selection | Error `_scope_push`, raw initialization | Existing explicit operations | Retain; no generic rewrite. |
| Decorator that already owns whole-entry cleanup | `$lisp.entry` | Existing push plus defer | Retain unless its complete body is independently rewritten. |

## Macro names: a real source mismatch, retained boundary

`lib/macro-value.x` contains 834 lines. Its five underscore functions are:

| Declaration | Source range | Lines | Consumer |
| --- | --- | ---: | --- |
| `Macro_close` | 65-68 | 4 | `src/macros.x:3694` constructs its exact identifier. |
| `Macro_apply` | 70-73 | 4 | `src/expressions.x:552` constructs its exact identifier. |
| `Macro_pattern` | 185-189 | 5 | `Macro_case_pattern` and fixture `macro-sequence-case.x:22`. |
| `Macro_case_pattern` | 475-477 | 3 | Macro pattern quotation, compiler recognition, emitter recognition. |
| `Macro_case_capture_at` | 479-494 | 16 | Emitter constructs the exact native call and static site address. |

The neighboring public operations `Macro.inserted`, `Macro.typed`,
`Macro.binder`, `Macro.number_literal`, `Macro.declared`, and
`Macro.inserted_items` use dotted source spelling. The
underscore functions are also present in generated public module documentation,
so their source spelling is already exposed. They are not uncalled leftovers.

The exact consumers are `src/macros.x:3531,3694`,
`src/expressions.x:540-553`, `src/compiler.x:2302-2310`, and
`src/emit.x:1199-1207`. The latter two recognize `Macro_case_pattern` by
native spelling. The emitter writes `Macro_case_capture_at` directly into C.
The `MacroCaseSite` static storage and `MatchCaptureBuffer *` output belong to
that compiler/runtime crossing, not to an ordinary user output API.

Changing a declaration to `Macro.apply` would ordinarily produce the same
native name: `Compiler._method_spelling` at `src/parse.x:1947-1971` folds
owner/member into `owner_member`. However, the declaration also records method
facts at `parse.x:1925-1928`. Equal C spelling therefore does not prove equal
method lookup, reflection, generated references, or collection behavior.

The collector publishes name/type facts, including generated symbols at
`src/collect.x:679-695`. The SDK reads bound function spelling at
`src/meta-sdk.x:318-322` and exposes parameter types at 325-339. No extra
Macro-specific collector or SDK route was found. General method facts and
generated reference documentation are still source-facing observable changes.

Decision: retain all five declarations and all exact compiler consumers. Do not
add dotted forwarding functions, aliases, or a second registration owner merely
to make the surface look uniform. Treat these as compiler-native intrinsic
entries. New ordinary Macro operations continue to use dotted spelling. A
future intentional API redesign must specify lookup and documentation changes,
not claim compatibility from the emitted identifier alone.

History explains the boundary without making it permanent. Commit
`09bb76324` introduced macro values, application, and cases. Commit
`867fa2b7e` on 2026-09-30 moved their implementation from `lib/meta.x` to
`lib/macro-value.x`. The current forms continue that established native call
contract. This plan does not reinstate any restrictions from archived plans.

## References and pointers: census and private adoption

The broad scalar/handle pointer signature search found 83 lexical matches in
`lib/` and two in `src/`. These counts include declarations and callback
signatures; they are search hits, not 85 interchangeable output functions.
The two compiler matches are `Compiler._collect_ids` at `src/cache.x:93`,
whose `List *seen` is a memo table, and `worker_wait_any` at
`src/utils.x:413`, whose `long *pids` is an array. Both remain pointers.

The runtime matches fall into these concrete roles:

- Native iterator callbacks occur in `iter.x`, `file.x`, `list.x`,
  `string.x`, `path.x`, `symbolset.x`, `split.x`, and `lisp.x`. They conform
  to `IterNextFn` at `lib/iter.x:29`; retain their signatures.
- Lisp lambda activation pointers at `lisp.x:617,640,659,687` address arrays
  of values or a stored parent activation. They do not represent one output.
- Error pattern arrays at `error.x:908,935,949,991` and policy pairs at
  727,734 remain array pointers.
- Machine patch sites at `machine.x:401` and Macro fixed slots at
  `macro-value.x:740` are arrays. Keep them.
- Typed-map hash, equality, validation, and update callbacks at
  `typed-map.x:126-217` participate in its pointer-based generated core.
  Treat that callback family as one contract, not scattered outputs.
- Logger's `List *destination` at `logger.x:580` is retained until sink
  retirement. Keep its actual address and public signature.
- Compiler-emitted `x2c_match_site_try_*` at `match.x:1184,1204,1227`,
  `x2c_normalize_slice` at `common.x:852`, and `_update_var` at `map.x:91`
  remain native/generated boundaries.
- Split's strategy function pointer at `split.x:50,147` and its three
  functions at 154-187 form one private callback ABI. Keep it for this plan;
  the public `Split.try_next` already presents reference outputs at 254-257.

### Published pointer outputs remain unchanged

`Symbol.try_new` at `symbol.x:113-119` (284-line file),
`String.try_long` at `string-number.x:39-73`, and `String.try_double` at
89-98 (98-line file) remain pointer APIs. The scanner entry points also retain
their pointer signatures: `scan_block_comment_status` at 80,
`scan_number_typed` at 119, `scan_c_string_status` at 443,
`scan_symbol_literal_status` at 515, `scan_atom_status` at 587, and
`scan_next_line_col` at 715. `scan.x` contains 725 lines.

The reference-adoption record expressly retained the three native parser
operations because native declarations must match their target signatures.
Commit `9b34e9d02` on 2026-09-24 attached `meta native` to Symbol's existing
definition without changing its pointer output. Scanner pointer output
signatures descend from the initial source commit `4235c3837`.

Current code supports reference-native functions, so history does not prove
these APIs can never change. It proves a migration requires compatibility
decisions. `Compiler.func_signature` at `src/callables.x:1210-1219` retains
declared parameter types. Native normalization at `meta-native.x:484-503`
preserves reference markers. `Func._reference_argument` at
`lib/func.x:300-324` checks carriers and declared targets. Replacing `T *`
with `T &?` changes these signatures and caller source even if C parameters
remain pointers. Do not silently make that public change or add adapters.

### Exact private migration

Adopt references in these four functions, retaining their public entry points:

| Private function | Source range | Lines | Planned outputs |
| --- | --- | ---: | --- |
| `MatchPlan._first` | `lib/match.x:688-700` | 13 | Required `Var &out_match`, `List &out_bindings`. |
| `MatchPlan._replace_all` | `lib/match.x:741-752` | 12 | Required `List &out`. |
| `MatchPlan._replace` | `lib/match.x:921-930` | 10 | Required `Var &out`. |
| `_read_form` | `lib/lisp.x:977-993` | 17 | Required `unsigned &cursor`; optional `Var &?out`. |

The Match public operations already require present outputs before calling
these helpers. The neighboring `_all` at `match.x:716-725` already expresses
its required result as a reference. Preserve write-on-success behavior and
every result status. Inspect reference presence facts at each caller during
translation; if a caller lacks a recognized fact, use a direct presence guard
instead of inventing a stronger validator.

The reader has two callers: `Lisp.read` at `lisp.x:1760` and `_read_eval` at
1813. Both provide cursor storage. The former forwards an optional result,
while the latter supplies a local form. Keep absent-result behavior and the
cursor's error location writes. Public `Lisp.read` already uses references.

Retain the eleven scan status helpers in this batch. Converting their outputs
while preserving public pointer entry points would require explicit nullable
pointer-to-reference bridging in several entries. That makes a punctuation
cleanup less direct. They consistently implement the retained scanner pointer
contract; `_decimal_number` can keep its private optional reference because
`scan_number_typed` supplies a real local. Different layers may have different
source signatures when their actual boundaries differ.

## Scope brackets: complete corpus and ownership

After removing comments, search found 20 `$scope` uses in runtime code and
14 in compiler code. It found seven runtime `Scope.push` calls, fourteen
runtime `Scope.pop` calls, and one of each in compiler code. The four Scope
definitions themselves were excluded from those call counts. The raw search
also found `Scope.push`, `pop`, `retain`, and `release` declarations/definitions
in `scope.x`; documentation examples are not implementation candidates.

| Owner | Manual calls | Existing `$scope` uses | Decision |
| --- | --- | --- | --- |
| `lib/context.x` | push 308; pop 303,348,349 | none | Retain persistent cross-call stack and rollback owner. |
| `lib/error.x` | pushes 360,1323,1340; pops 274,362,590,611,658,763,1007,1343 | none | Retain floor/conditional/initialization operations in this plan. |
| `lib/lisp.x` | push 1730; deferred pop 1731 | 497,649,1110,1643,1704,1869 | Entry decorator already expresses full-entry cleanup; retain. |
| `lib/match-cache.x` | push 551; pop 561 | 130 | Ordinary lexical constructor bracket; adoption candidate. |
| `lib/thread.x` | push 208; pop 212 | none | Retain coordinated pool sealing and shutdown sequence. |
| `src/meta-group.x` | push 815; pop 817 | none | One native reset call bracket; adoption candidate. |

The remaining `$scope` sites are `lisp-targets.x:214,219`,
`logger.x:396,421,588,632`, `list.x:752`, `match.x:1117,1130`,
`pool.x:845`, `symbolset.x:230`, `var.x:742,1272`,
`collect.x:89,104,108,652,1128`, `compiler.x:2577`, `literals.x:607`,
`macros.x:4308,4391`, `meta-helper-client.x:376`, and
`meta-native.x:720,829,912,926`. These establish that the construct already
composes with creation, copy, return, dynamic native calls, and statement bodies.

`Scope.push` keeps its `Scope *` because the active stack retains the slot's
address after the call. `Context._open` publishes its Scope until `close`, not
until `_open` returns. Its failure defer restores Match, Error, Pool, and Scope
in reverse order at `context.x:299-305`. A lexical `$scope` would close the
wrong lifetime. The same pointer rule governs Logger's destination output.

`$scope` expands through `src/builtins.x:25-31` into entry plus deferred exit.
The book at `docs/src/guide/system-macros.md:255-325` specifies once-only
destination evaluation and restoration on every exit. `src/regions.x:159-161`
recognizes the same emitted Scope names for region effects. No new effect
ledger or wrapper is needed by these substitutions.

Error `_scope_push` at `error.x:1320-1326` pushes only when needed and checks
the error-floor boundary. Raw initialization at 1336-1347 runs before Error
becomes ready. Exception cleanup registration at `exception.x:75-79` itself
uses per-thread runtime state. These are reasons to preserve the current
sequence until a focused failure-path investigation establishes substitution,
not evidence that `$scope` cannot ever serve Error code.

### Exact lexical migration

1. In `MatchCache.new`, `lib/match-cache.x:550-562` (13 lines, 580-line file),
   declare the result outside `$scope(&owner)`, keep all constructor writes
   inside, and return after the bracket. Preserve allocation owner and bucket
   initialization. Do not add a constructor cleanup framework or change the
   documented requirement to dispose the cache. Compare its generated entry,
   normal pop, and unwind cleanup with existing `$scope` sites. The original
   bracket moved intact from `match.x` in `904234f9f` on 2026-09-30; the move
   is provenance, not evidence of a deliberate prohibition on `$scope`.
2. In `Compiler._stage`, `src/meta-group.x:813-818` (six-line containing
   branch), replace only push/reset/pop with `$scope(&session_meta_scope)`
   around the reset call. Preserve `meta_group_bound` update ordering and
   `x2c_module_reset` call arguments. Do not expand the task into rollback of
   module registration. A failed callback currently skips the plain pop;
   restoring the caller destination follows the lexical-bracket contract.
   Record this failure-path difference explicitly during implementation.

No claim of a reproduced failure is made. These substitutions are scoped to
existing lexical bracket semantics. Do not migrate Error, Thread, or Context
by analogy, and do not use `$scope()` where selecting a destination is needed.

## Reconcile concurrent and recorded work

The value/reference style campaign is already delivered through PR #76,
`cbecd92e`, and `a373970c`. Its records expressly retain array pointers,
native callbacks, and parent references. Follow its current convention without
reopening representation decisions or migrating public contexts again.

F14 selected `JobLaunch`; commit `f0d3e1f29` on 2026-10-02 delivered that name.
Current `lib/process.x` already uses it. Do not rename it back to `Launch`,
introduce an alias, or count it as unfinished style work. F29 release
consolidation landed in `79e8bc648` on 2026-10-02. Current
`machine.x:476-486` has one release body in `drop`, with `free` and
Cleanup's value receiver forwarding to it. Retain the value cleanup adapter
and exported construction/lifecycle contracts. This plan does not own F14/F29.

The active post-integration F30 asks about source/native method spellings and
metadata consumers. Macro naming is retention here; do not turn that package
investigation into a global ABI rename. The active quotation-adoption work
owns code-building templates. This plan adds no AST quotation mechanism and
does not duplicate its compiler work. The scalar ledger and Lisp callback
adapter projections from the broader idiom survey belong to separate plans.

The parallel AST ownership plan moves structural `ast_*` helpers from
`type.x` to `ast.x` while initially preserving their exported names and ABI.
That agrees with this plan: settle the owner first, retain established native
identifiers, and examine source-facing names separately. Do not convert every
flat export into a dotted method or invent an `Ast` wrapper namespace solely
to obtain one spelling.

Before implementing, read the current four target function bodies and two
brackets on current `origin/dev`. If another session already migrated them,
close the corresponding item with its revision and verify the same contracts;
do not replay stale line numbers or reintroduce an older implementation.

## Implementation and existing validation

Perform private reference adoption and lexical bracket adoption as separate
coherent changes if their evidence or dependencies differ. There is no new
mandatory intermediate commit, gate, planning round, or publication sequence.

1. Start from current `origin/dev`, preserve other work, and establish the
   delivery context required by the root instructions for implementation.
2. Make the four private reference migrations only. Read every actual caller
   and retain absent-output cases; do not use unrestricted text replacement.
3. With a compiler already available, translate the affected modules and
   inspect C parameter types, public generated declarations, and direct callers.
   Compare reflected public signatures before and after. Public signatures
   and exported names must remain unchanged.
4. Use the existing `match_suite`, `match_plan_suite`, `match_cache_suite`, and
   `lisp_suite`. Build the existing test runner, then select these suites as
   documented in `agents/quick-start.md`. Do not add mirror tests for signature
   punctuation. Existing compiler fixtures `macro-sequence-case`,
   `optional-reference-initializer`, and `meta-output-cells` remain relevant
   compatibility evidence if compiler changes accidentally become necessary;
   such compiler changes are outside this private adoption design.
5. Make the two bracket substitutions. Inspect generated cleanup placement;
   verify normal return and Error transfer restoration with an inert focused
   probe if existing suites do not exercise the changed call. Use existing
   `scope_suite`, `defer_suite`, `context_suite`, `match_cache_suite`, and
   meta-group/native-module checks appropriate to the actual changed behavior.
   No recurring check or permanent failure-injection mechanism is proposed.
6. Review and fix the completed authored diff before publication validation.
   Check that retained native boundaries did not change, public documentation
   did not gain aliases, and no producer guarantee was duplicated. Follow the
   existing root delivery and final-tree gate; do not run broad gate components
   separately just to publish. Planning-only delivery runs no code gate.

The private signature migration should not affect native runtime throughput.
The lexical bracket substitutions can change cleanup registration. Apply the
existing performance checkpoint rule if their actual generated code reaches a
hot path; do not infer a performance gain or require a new measurement gate.

## Plan review

Public callers and native declarations establish the five Macro names and
published pointer signatures. Match callers establish required outputs; Lisp
reader callers establish the cursor and optional result. Scope producers
establish destination storage and lifetime. No proposed consumer rechecks tag,
allocation, callback arity, or pattern guarantees.

The refreshed Macro producer establishes scalar-sequence lifting and Name
declaration holes. The refreshed public-meta emitter establishes weak copies
for public functions, and the public-object partitioner owns header qualifiers.
This plan retains all three contracts and adds no parallel name, linkage,
signature, or qualifier policy. The four private outputs and two brackets
remain unchanged on the refreshed baseline.

The design reuses references and `$scope`, deletes four private pointer-output
spellings and two manual lexical bracket sequences, and preserves native
callback, array, retained-slot, and cross-call owners. No helper, representation,
traversal, cache, adapter ledger, or public forwarding family is added.

The resulting source uses ordinary x2c borrowing and lexical lifetime syntax.
It keeps compiler-native identities explicit where emitted code consumes them.
It does not import a framework or make unrelated lifetime policies identical.

No validator or dedicated diagnostic is proposed. No permanent negative fixture
is proposed. A temporary unwind probe, if needed, establishes restoration of
the caller's active Scope after Error transfer. It does not add a new failure
policy or a recurring process requirement.
