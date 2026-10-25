# Native compiler with runtime Lisp

> Status: landed
> Approved design, 2026-10-25. Implemented, validated with
> `agent-pr-check`, and published to `dev` on 2026-10-25 with Gary's
> approval.

## Result and compatibility

Compile x2c through native x2c macros and meta functions. Bootstrap and staged
compiler executables must neither link nor evaluate the Lisp interpreter.
Keep canonical Lists, structural AST acceptance, quotations, non-Lisp template
splicing, and ordinary `$name(...)` meta calls. Do not authenticate AST origin.

Remove compiler `$(...)` and `@(...)` Lisp forms. Migrate owned consumers and
document this deliberate language change. Lisp remains available for runtime
DSLs and the REPL. Preserve implicit runtime Lisp declarations; do not require
programs to add an explicit include. Preserve runtime APIs and the convenient
`$lisp.bind`, `$lisp.binding`, and `$lisp.install` authoring surface. Decorated
functions remain callable both natively and from runtime Lisp. Public binding
macros create fresh Func handles; compiler inventories retain shared handles.

Native meta functions may deliberately use runtime Lisp in a full-runtime
project helper. Compiler-loaded modules use the compiler's core runtime
exports. A meta function requiring Lisp must execute in the full-runtime helper
or REPL host. This intentionally removes Lisp exports from the compiler host;
no owned compiler-loaded module requiring them was found during planning.

This plan supersedes the easy-wins limit in
[compiler-lisp-independence.md](compiler-lisp-independence.md). The earlier
instruction to leave `$lisp.bind` unchanged now means preserving its public
behavior through a native rewrite. Runtime Lisp definition, inheritance,
callback, and session rules remain unchanged.

## Native binding ownership and precedence

Replace `macro_lisp` with a small `MetaBindings` active name-to-Func table.
Keep declaration/signature metadata (`native_meta`), provider advertisements
(`project_meta`), linked inventories, and loaded-module inventories in their
existing distinct roles. Do not mirror a Lisp namespace or create a generic
Var registry for `meta static` data. Native groups retain their existing
initialization and reset owners.

Allocate the `MetaBindings` record inside its binding Scope, following the
existing `Lisp.kernel` lifetime pattern. Creation under a child Context must
not leave the record in that transient Context. Keep a separate values Scope
for the lifetime currently supplied by `Lisp.user`; the table and stubs belong
to the binding Scope. Carry the record and borrower state through existing
compiler segment handoff. Destroy values before the binding Scope.

Ordinary native calls and delayed class recipes use the values Scope. Preserve
the existing direct linked-call path in the caller Context. Reuse Func
adapters, project stubs, helper transport, `MetaContext`, and linked-definition
hash selection. Do not change Pool ownership or add a new lifetime framework.

Preserve source macro precedence, source-ordered provider installation,
private/static bindings, signature certification, builtin precedence, and
selected-module order. Resolve explicit meta callees when the macro definition
is parsed, using ordinary declarations. Do not change `using` semantics.
Compiler Lisp overrides and inherited compiler Lisp bindings disappear with
the evaluator; do not retain their precedence rules in the native table.

## Early declarations and bootstrap ordering

Add ordinary `lib/common-types.x` to own the existing Var union and List/Mutex
aliases, moved from their current owners without duplication. Use a root
runtime source with normal generated `.h`, `.c`, `.xi`, and `.o` outputs.
Do not use `lib/common/types.x`: current source discovery skips that path, and
emission would reference an unbuilt `types.h`.

Add `etc/compiler-prelude.x` with this order:

1. Include the foundation types.
2. Declare ordinary bodyless native meta prototypes.
3. Define builtin macros and keyword aliases.

Collect and replay this syntax source before the runtime prelude,
unconditionally, including internal `c.prelude=false` compilation of
`lib/x2c.x`. Keep `Compiler.prelude_sources()` ordering, with `lib/x2c.x`
first; some `.cdr` consumers depend on it. Supply the syntax source separately.
There is no public `--no-prelude` flag to preserve or introduce.

Remove the embedded macro-only installer from `start_collection` and
`_reset_macros`. Use ordinary collection and source-effect recording. Full
parse reset restores syntax effects before runtime effects. Remove the obsolete
suppression of `builtin_defs` in effect recording, preserve private/source
rules, and carry `builtin_defs` into collection shadows so ownership survives.

The early prototypes name existing expansion algorithms:

```c
meta List _x2c_scope_expand(List, List);
meta List _x2c_with_expand(List, List);
meta List _x2c_foreach_expand(List, List, List, Var, Var, Var, Var, Var);
meta List _x2c_auto_expand(List);
meta List _x2c_class_expand(List);
meta List _x2c_foreign_alias(List, List);
meta List _x2c_callback_adapt(List, List);
```

The last two are small AST constructors. Captured List/Var arguments remain
AST values under existing staging rules; early Code/Type aliases are not
needed. Define `$scope` first. Auto region and destination forms delegate to
ordinary `$scope()` and `$scope($destination)` decorators. `_auto_release` can
receive its native prototype after the full meta declarations become available.
The scalar macro already takes its `x` parameter directly; it needs no
`Code.arguments` query. Add no parser exception, synthesized prototype path,
second evaluator, or new macro binding rule.

## Native targets, callbacks, and iterator calls

Separate the compiler's genuine native runtime inventory from the Lisp-facing
callback adapter inventory. Keep compiler intrinsics/builtin registration
separate from runtime native targets and retain current lookup precedence.
Reuse existing target/signature builders. The compiler inventory includes
native Func callback parameters; runtime Lisp keeps its adapter selection and
exclusions. Cache the native inventory lazily in the existing native-module
Scope. Do not add unconditional shared Func initialization work at startup.

Handle an omitted iterator destination at the native invocation boundary.
Use the `native_meta` declaration signature, only for declared native iterator
operations with exactly one missing final argument. Append `Iter.new` in the
values Scope. Explicit destinations remain unchanged. Preserve raw Func
signatures and existing argument-count/type checks; do not add a
`Func.rest_context` API or an interpreter closure.

The REPL must resolve runtime-side Lisp natives and callback adapters first.
Blindly copying the compiler Func table would break cases such as `List_map`,
whose lowerer passes an interpreted lambda to a Lisp adapter. Reuse the runtime
native resolver, including existing `Lisp.eval` binding selection where useful,
and fall back to compiler targets for program/module functions. Preserve
callback budgets, truth semantics, lazy ownership, and runtime native ABI.

## DSL decorators and native generators

Expose the existing signature computation as an ordinary public meta query:

```c
meta List Code.native_signature(Code value);
```

Delegate to `Compiler.func_signature`; do not duplicate signature inference.
Add ordinary optional `lib/lisp-bindings.x`, included through the existing
implicit Lisp module. Replace the old `etc/` macro source and lazy installer
lookup. Include meta/compiler-private query declarations, not the Lisp
implementation: including it would create a cycle and unwanted link edges.
Runtime `Lisp.bind` names in macro templates resolve when expanded.

Use a native `_binding_statement` or shared statement builder. Construct the
signature literal through `MetaContext.literal_list`; do not splice a returned
signature List as executable AST. Retain `Func.new` freshness instead of casting
a shared handle. Reset `binding_rows` and `binding_sealed` at the same parse
resets as the old lazy installer. Preserve group ordering, sealing, duplicate
behavior, and source function bindings.

Convert target filtering, linked hashes, prelude records, SymbolSets, and class
recipes to native calls through their existing owners. An optional ordinary
`lib/compiler-meta.x` can hold compiler-private native prototypes needed after
full types. `Code.native_signature` is the only new public SDK query required.

Keep the C-only declaration boundary for `lisp_native_targets`. A pure meta
static helper returns `%((preproc "extern Map lisp_native_targets(void);"))`.
Keep the Unit macro `$lisp.native.declarations` around that helper, because
`_code_result` recognizes this preprocessor List through the macro boundary.
The helper can live in `lib/lisp-bindings.x`, where `gen-linked-meta` sees its
top-level meta body. Do not expose an ordinary source prototype in `.xi`, and
do not call the interpreter to produce the C declaration.

## Shared reader, scalar access, and native linking

Extract the shared grammar to ordinary `lib/datum-reader.x`. Include
`tokenizer.x` and `scan.x` explicitly. Use these entry names:

- `datum_scan_tokens`
- `datum_read_token_form`
- `datum_read_form`

Both datum and Lisp include the reader unit. Do not include `datum.x` from
Lisp, which would expose optional helper-transport declarations in the implicit
prelude. Add `datum-reader.x` to `OPTIONAL_SOURCES`; transitive Lisp declarations
remain implicit. Keep `Lisp.read` as the ABI wrapper. `Lisp.eval_string` scans
once and uses the token-stream entry. Preserve the datum fast path and change
only its reader fallback. Retain prefixes, comments, escapes, cursors,
diagnostics, depth behavior, canonical List ownership, and transport format.
There must be one grammar implementation.

Move `NativeScalarLoad`, `NativeScalarStore`, `NativeScalarAccess`, generated
records, and their lookup/table into existing `native-scalar-types.x`.
Preserve C names, layout, signatures, and inclusion from the Lisp header.

Keep full `libx2c.a` and `libx2c-dev.a` artifact roles. Link the compiler with
the existing runtime object list filtered to omit `lisp.o` and
`lisp-targets.o`, instead of force-loading the full archive. Mirror this in
`bootstrap/src/Makefile`, deriving objects from generated `.c` sources rather
than requiring existing `.o` files. Retain platform export flags and full
archive build prerequisites. Commands, `x2c-build`, REPL, and project helpers
keep full-runtime links. Add no new archive variant or packaging redesign.

## Bootstrap transition and owned migration

Implement in a separate isolated local worktree, in this dependency order:

1. Add the native capabilities, prototypes, syntax prelude, and query. Retain
   Lisp assets and compatibility aliases required by the old seed. The old
   seed must not need an operation before it can compile its implementation.
2. Build the capability compiler with the old seed. Regenerate bootstrap
   through normal targets before adopting capabilities the seed cannot read.
3. Migrate owned consumers in `src/`, `lib/`, `etc/`, `commands/`, `tools/`,
   packages, examples, tests, documentation, and editor support. Keep runtime
   `.xlisp` assets and DSLs. Use binding-aware transformations.
4. Replace the compiler binding/call owner. Remove compiler Lisp loading,
   parsing, imports, queued effects, and obsolete SDK assets. Use the compiler
   prelude as the home marker and include it in installed/release payloads.
5. Apply core-only compiler linking. Refresh final generated artifacts and
   rebuild the combined compiler from its shipped bootstrap.

Never hand-edit bootstrap C/H. If ordinary source ordering cannot support the
transition without an architectural exception, return to review. Do not add a
fallback evaluator. Retain semantic coverage when a native behavior test was
previously written through Lisp. Replace compiler-Lisp-only fixtures with
located unsupported-syntax diagnostics. `$(` inside strings, comments, and
runtime DSL data remains data; do not reject it by text search.

## Simplification estimate and acceptance

The planning estimate is **200-350 fewer authored production-code lines**.
The firm acceptance minimum is **200 net authored production-code lines
removed**. Retaining the interpreter and REPL limits the possible reduction;
this is not a claim that thousands of runtime lines will disappear.

The inspected removal/replacement pool at `0650e2882` contains 573 code lines:

| Existing area | Code lines |
| --- | ---: |
| Compiler Lisp loader, sessions, and imports | 293 |
| Lisp template evaluation and scratch rewriting | 68 |
| Lisp slot parsing and construction | 52 |
| Queued Lisp declaration effects | 39 |
| Lisp/import diagnostics | 28 |
| Included Lisp/import effects | 17 |
| Frontend Lisp preload | 38 |
| Private SDK Lisp binding bridge | 10 |
| Top-level Lisp parser helper | 9 |
| Compiler-only `.xlisp` files | 19 |
| Total gross replacement pool | 573 |

This pool is not net savings. Estimated replacements consume 200-380 lines:
native binding storage 45-80; calls/stubs/iterator handling 35-70; early loading
and declarations 40-90; native generators 35-80; runtime/REPL bindings and
diagnostics 45-60. Further edits can consume this headroom. These estimates
support the target but do not prove that it has been achieved.

The measured core production baseline at `0650e2882` is:

| Source group | Code lines | Physical lines |
| --- | ---: | ---: |
| Compiler | 41,163 | 55,010 |
| Runtime | 22,749 | 37,015 |
| Support | 681 | 868 |
| Production Lisp | 298 | 401 |
| Total | 64,891 | 93,294 |

This inventory covers tracked `src/**/*.x`, `lib/**/*.x`, `etc/*.x`, and
production `.xlisp` in those roots. It excludes generated `src/linked-meta.x`,
`lib/x2c.x`, and `etc/meta-queries.x`. The measurement used `cloc` with C-style
comment handling for both source suffixes, matching their actual comments.
Generated outputs are not evidence of authored-code reduction.

Record a fresh implementation baseline. At completion compare against the
same integrated upstream tree without the campaign, excluding unrelated dev
changes. Charge every replacement, new helper, and new production validation
to the campaign, including changes outside the core inventory in commands,
REPL, tools, and packages. Exclude tests, docs, examples, generated code,
comments, and blank lines from the production-code savings. Report their
changes separately. Moves and extractions of reader, scalar, or type code
count as zero deletion. Physical authored production lines must also decline.
Do not compress formatting or delete unrelated code to meet the minimum.

Use existing `cloc`, Git, and repository tools for one final before/after
report. Do not add a metrics framework or recurring gate. The report must
also assess these concrete simplifications:

| Dimension | Required result |
| --- | --- |
| Mandatory compile-time authoring languages | x2c + Lisp (2) becomes x2c (1). Repository-wide language count stays unchanged because runtime Lisp remains. |
| Compiler mental models | Remove compiler Lisp sessions/inherited namespace, scratch globals/string rewriting, interpreted iterator wrappers, and Lisp-specific compiler binding rules. |
| Reasoning context switches | Remove the need to follow native compiler logic into an interpreter environment to understand ordinary expansion. Count developer/execution contexts, not OS scheduler switches. |
| Execution barriers | Remove x2c-to-Lisp-to-native crossings and text-to-runtime-form evaluation from representative builtin expansion paths. Keep required typed AST binding, helper IPC, native ABI, and bootstrap boundaries. |
| Replacement machinery | Add no interpreter, mirrored namespace, duplicate parser, or extra process boundary. Justify each lasting helper and each new owner-boundary check. |

Passing correctness checks alone does not complete the campaign. If the
200-line minimum, physical-line decrease, or complexity criteria fail, stop
and review with Gary. Do not silently lower the target, expand scope, or add
unrelated deletions. A more complicated compiler is an unsuccessful outcome.

## Review and validation

Review bootstrap ordering and binding/lifetime/callback design independently,
then review the final combined authored and generated diff. These are bounded
campaign reviews, not new per-commit or recurring process requirements.
Planning is based on source inspection and earlier probes; implementation and
bootstrap proofs have not yet been performed.

Use focused checks for the affected boundaries:

- Cold/warm collection, syntax-prelude replay, builtin keyword ownership,
  private/static/provider order, and declaration-producing macros.
- Segment handoff and stub survival, native callbacks, omitted/explicit Iter
  destinations, delayed class recipes, and initialization timing.
- Native/Lisp dual callability, fresh public handles and shared inventories,
  binding group ordering/duplicates/sealing, implicit declarations, and the
  C-only preprocessor declaration boundary.
- REPL persistence, callbacks, native calls, interruption, load/reload, and
  scalar/record access.
- Reader parity, multiple forms, datum/helper round trips, and ownership.
- A native meta helper that intentionally uses runtime Lisp and returns an
  integer and a canonical AST List.
- Native link/symbol inspection of bootstrap and staged compilers: exclude
  `Lisp_kernel`, `Lisp_new`, `Lisp_eval`, `Lisp_apply`, and
  `lisp_native_targets`, using actual emitted symbol spellings. Full runtime
  and REPL must retain the corresponding APIs.

Use existing stage comparisons, cold collection checks, relevant configured
package/native checks, and `tools/gate-state.py ensure agent-pr-check` for the
future completed implementation. Inspect generated deltas. Measure relevant
performance from the same absolute path with the corrected flat-interface
lookup present in both trees. Distinguish CPU instructions from elapsed time;
check startup/shared Func initialization without assuming its cost. Add no
recurring gate or expanded readiness target.

For this plan-only delivery, use `tools/gate-state.py ensure doc-check`.
Do not run the implementation publication gate merely to save a plan.

## Delivery and handoff

Publish these approved planning documents to `dev`. This authorization does
not authorize implementation here or publication of future compiler changes.
Another executor starts from current dev in an isolated local branch and
worktree, records the implementation baseline, and follows the bootstrap
transition above. Keep implementation commits local. Do not push them, create
a PR, or advance dev/main until Gary separately directs delivery. Review the
completed simplification report with the implementation evidence.

## Plan review

Ordinary declaration binding establishes callee identity; native signatures
and Func invocation already own argument contracts. Staging establishes AST
value transport, source effects establish replay order, and Scopes establish
lifetimes. Consumers rely on those facts instead of rebuilding validators.
Canonical Lists remain accepted by structure regardless of their producer.

The design deletes compiler Lisp sessions, evaluation, imports, scratch
rewriting, and compiler-only SDK assets. It reuses expansion algorithms,
signature builders, adapters, helper transport, native groups, and source
collection. `MetaBindings` replaces the removed active binding owner. The
values Scope preserves an existing lifetime. The syntax prelude supplies
ordinary declarations before macros. The reader extraction supplies one
shared grammar, and the scalar move removes a link dependency. These are
replacement owners rather than parallel frameworks.

Native meta functions, ordinary prototypes, literal templates, canonical
Lists, and current ownership rules express the result directly in x2c. No new
parser mode, evaluator, generic registry, process boundary, or archive family
is required. The minimum reduction and final complexity assessment prevent
small local conveniences from defeating the simplification goal.

No new general validator is proposed. Retain existing signature/arity checks
at the native call boundary. Add only the located unsupported-syntax
diagnostic and focused negative fixtures needed to establish intentional
removal of compiler Lisp forms; they protect the documented compatibility
change. Binding duplicate/sealed and reader failure cases exercise existing
contracts. Do not add earlier or more specific rejection when the owning
boundary already guarantees correctness.
