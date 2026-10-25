# Compiler independence from Lisp

> Status: active
> Local work authorized by Gary on 2026-10-24, starting at `9e68d6b`.
> Preserve canonical Lists, the REPL, and runtime Lisp. No pushes or PRs.
> Reconciled with predecessor PR #285 at `5f7274f978b7749e5d2d9cad1b218ea99277ea2b`.
> Gary authorized local replay and combined validation on 2026-10-24.
> The independent source changes are replayed on `5f7274f` in
> `codex/lisp-independence-pr285`; combined local validation passed.
> Current dev `a90359210` is integrated locally; reassessment and fresh
> combined validation passed. Scalar forwarding is implemented and validated
> locally. All selected changes remain unpublished.
> The two compiler-owned Func inventory wrappers are implemented locally;
> signature, identity, lifetime, initialization, and full local checks pass.
> Harder cases remain deferred. No push, PR, or publication is authorized.

## Result and boundaries

Follow [PR #285](https://github.com/gwf/x2c/pull/285), which owns the
straightforward source conversions, with the independent reader and linked
meta session changes. Keep source syntax, canonical values, helper messages,
interface formats, native target selection, and the REPL execution model
compatible. Do not deliver the same embedding conversions twice.

This batch does not promise a compiler that never initializes Lisp. Native
meta dispatch, early built-ins, and public compile-time Lisp still use the
shared environment. Do not replace that environment with a second registry.

## Compiler-owned Func inventories

Gary authorized this follow-up on 2026-10-24, based on local `3a36f3885`.
Replace only `$builtin.row` in `src/builtins.x` and the generated
`$linked.row` in `tools/gen-linked-meta.sh` with ordinary `(Func)` conversion.
Regenerate `src/linked-meta.x` through its generator. Leave `$lisp.bind` in
`etc/lisp-bindings.x` byte-for-byte unchanged. Do not extend this change to
native target generation, binding precedence, callbacks, or early queries.

The two inventories still return fresh Maps with the same names and native
signatures. Their 14 built-in and 226 linked Func handles now use the
existing direct-conversion owner: a shared handle per target, with program
lifetime. Repeated inventory calls reuse those handles. Unit initialization
creates them before main instead of constructing them with each Map. This
identity and initialization change is intentional and local to these two
compiler-owned inventories; public binding macros retain fresh handles.

Design review: both paths use the existing `Compiler.func_signature` and
native adapter owner. Current identity consumers compare against the stored
inventory entry; none require a new Func from a repeated inventory call.
Literal preparation precedes shared handle initialization. No new registry,
allocator, lock, public query, or lazy initialization layer is selected.

The paired probe links the same probe object and runtime archive against
the baseline and candidate compiler archives. The baseline archive is saved
from the converged stage 1, whose inventory C/H matches the saved pre-edit
stage 0. A separate pre-edit run also records the original behavior.
The probe checks all 240
signatures, repeated-call identity, representative invocations, handle
survival after the creating Scope closes, and public `$lisp.bind` freshness
and session independence. Startup and first/second inventory-call Scope
allocation counts locate the initialization phase. Fresh Maps now compare
equal by content because their values share identity; their storage remains
distinct. These are allocation
observations, not elapsed-time performance results. Logs and probe paths
are retained under `debug/func-inventory/`.

The paired probe passes all 240 name/signature comparisons, identity and
Scope-lifetime checks, and representative calls. Public `$lisp.bind` still
produces distinct handles in successive sessions, and destroying one session
does not invalidate the other. Its source hash is unchanged.

| Paired probe observation | Baseline | Candidate |
| --- | ---: | ---: |
| Scope allocation calls before main's first statement | 1,060 | 1,300 |
| Live Scope allocations there | 747 | 987 |
| Live requested payload bytes there | 673,063 | 684,583 |
| Allocations in each built-in inventory call | 35 | 21 |
| Allocations in each linked inventory call | 263 | 37 |
| Handles reused by the second inventory call | 0 | 240 |

The startup difference is exactly 240 handles and 11,520 requested payload
bytes. The first calls to both inventories allocate exactly 240 fewer
handles, so this moves those allocations before main. Repeated calls reuse
the handles. Counts exclude allocator metadata and Pool backing storage.
An additional paired probe initializes both inventories from another unit's
pre-main initializers, then checks all names/signatures and representative
invocations in main. Both baseline and candidate pass. The generated public
headers remain byte-identical; shared-handle declarations increase by 14 in
builtins and 226 in linked meta, using the existing initializer mechanism.

The first candidate probe incorrectly used Map content inequality to check
distinct Map storage. Correcting the probe to compare addresses made both
versions pass; the final probe also explicitly checks their changed content
equality. `probe-map-equality-initial.log` retains that initial failure.

The controlled comparison uses one link command for both variants. A
separate driver-linked final candidate also passes all signature, identity,
lifetime, and early-initialization checks. Its aggregate startup counters
are recorded separately in `evidence.json`; inventory-call allocation counts
match the controlled pair. These observations locate initialization, without
claiming an elapsed-time improvement.

| Inventory follow-up check | Result | Local evidence |
| --- | --- | --- |
| Baseline/candidate signatures, identity, lifetime, and public binding | All 240 signatures match; Maps remain distinct; candidate handles survive Scope closure; public `$lisp.bind` remains fresh. | `baseline-paired.log`, `candidate-paired.log`, `comparison.log` |
| Pre-main initialization from another unit | Both variants initialize and invoke successfully. | `early-initialization.log` |
| Exact final-stage archives | All focused checks pass. | `final-candidate-probes.log` |
| `make build`; `make doc-generate` | Pass. | `build.log`, `doc-generate.log` |
| Full `make agent-pr-check` | Pass, including all five existing extended steps. | `agent-pr-check.log`, `gate-steps/` |
| Bootstrap and cold comparisons | All 302 C/H files match across bootstrap/stages 0/1; all 430 cold C/H/.xi files match stage 1. | `agent-pr-check.log`, `gate-steps/proof-cold-collection.log` |
| Unit suites | 1,045 pass, zero failures/skips, 27,250 assertions. | `gate-steps/verify.log` |
| Compiler fixtures | 1,288 pass, 2,848 checked artifacts. | `gate-steps/verify.log` |
| Documentation and commands | All 119 executable examples match; all command checks pass, including REPL inspection, reload, and source loading. | `gate-steps/` |

The authored diff is limited to the two wrappers and their ownership
comments. Generated `src/linked-meta.x` comes from its generator. The two
bootstrap C deltas add standard shared-handle initialization, replace row
construction, and renumber literal-cache references. The generated API pages
state Map ownership and shared handle lifetime. Public headers remain
unchanged. No generated file was edited by hand.

Source hashes stayed unchanged during validation. No recurring check or
process step was added. Package suites and elapsed-time performance were not
rerun for this compiler-only follow-up. The local Make result is correctness
evidence, not a publication receipt. All harder cases remain deferred; no
push, PR, or integration enrollment is authorized.

## Reassessment after current dev integration

Gary requested local integration of current `dev` on 2026-10-24. The fetched
revision is `a90359210b4fd4cf130b1e3138a7c8cf6d38ae12`, 30 commits beyond
the PR #285 base, changing 305 files. The pre-integration local batch is
checkpointed at `2eac34b1`; its earlier recovery stash is also retained.
No push, PR, or shared-branch update is authorized.

The source merge preserved every independent change. Only generated
bootstrap/API files and the plan index conflicted. Generated files start
from current dev and are regenerated through repository targets. The index
keeps this plan and accepts the upstream archival of the with/alias plan.

| Upstream change | Effect on this batch and remaining plan |
| --- | --- |
| `with` temporary assignments replace `$let` | Keep the new syntax in all merged callers. The old Lisp `Code.type` slot is gone, but `etc/builtin-macros.x` still invokes `with.expand` through Lisp. Its algorithm is native in `src/builtins.x`; eliminating this call still needs the deferred early-bootstrap design. |
| Lexical `alias`, file/static alias scope repairs, and `unalias` | Keep these source-binding features and their tests. They store canonical syntax in Sym facts or the existing macro Map and replay include effects. They do not replace the ordinary native/Lisp callable environment. |
| Native/meta context code migrates to `with` | Retain the upstream save/restore blocks. The independent patch still only moves session initialization from the two entry points to ordinary lookup. |
| Datum decoding uses a String switch | Keep upstream dispatch and the existing full-reader fallback. The reader/session change still supplies canonical prefix names without constructing a session. |
| Compiler/command name dispatch uses String switches | Keep upstream algorithms; no conflicting evaluator replacement is present. |

The previous binding precedence decision remains the compatibility premise.
`_shipped_callee` and `_apply_linked` still own shipped direct calls;
`_meta_function` still initializes the session before ordinary lookup, and
`_bind_advertised_meta` still preserves later Lisp definitions. New expression
aliases additionally follow their documented lexical and include scope rules;
they are not another callable registry.

Alias installation and removal are now additional source-ordered effects.
`src/macros/invocations/recognition.x` handles their native branches separately
from Lisp/import effects. `_rebind_globals` in `src/macros/lisp.x` serves
imported aliases as well as cached macros; its location does not make that
AST traversal evaluator work. Preserve those consumers in any future split.

### Scalar forwarding follow-up

The original hard-case grouping was too broad for `lib/common.x`'s `$scalar`.
Before this follow-up, the template had three `Code.arguments` Lisp splice
sites, but all nine instantiations passed exactly their own type and a
parameter named `x`. Declaring and forwarding the parameter inside the
template needs no early native declaration or replacement callable registry.

A scratch macro with that simpler input shape compiled and ran at the dev
reassessment. Its nine scalar cases matched existing boxing kind and
value, display String, and readable representation. The float case retained
`Var.new` and `<f32>`. That prototype established a focused implementation
path; it did not establish complete scalar edge-case parity or change the
repository's macro itself.
The prototype and result are recorded in
`debug/dev-reassessment/scalar-feasibility.log` and `probe-root.txt`.

Gary authorized this follow-up on 2026-10-24. The nine repository calls now
pass only their type, boxer, and optional prefix. The macro declares its
own `$type x` and directly forwards `x` in all three generated methods.
The old captured parameter and three `Code.arguments` Lisp slots are gone.
The only book mention of `$scalar` uses it as a documentation-generation
example; no caller outside these nine generator invocations was found.
No compatibility wrapper or new compiler query is needed for these callers.

The public methods keep their signatures, source parameter names, and
documentation. A before/after compiler projection comparison passes for all
183 common functions, including the 27 scalar methods with parameter `x`.
Generated C uses private parameter names; a comparison scoped to each
parameter binding confirms the 27 method bodies are otherwise identical in
both `common.c` and `common.h`. Float still calls `Var.new` with `<f32>`,
including its existing promotion of signaling NaNs. The existing Var tests
exercise that behavior. No scalar algorithm or runtime signature changes.

Local validation passes, with logs under `debug/scalar-forwarding/`:

| Scalar follow-up check | Result | Log |
| --- | --- | --- |
| `make build`; `make doc-generate` | Pass; existing bootstrap accepts the change. | `build.log`, `doc-generate.log` |
| Compiler projection comparison | All 183 common function signatures and documentation match; all 27 scalar methods retain source parameter name `x`. | `signatures.log` |
| Generated forwarding comparison | All 27 method bodies match after bound parameter renaming in both C and header output. | `generated-forwarding.log` |
| Full `make agent-pr-check` | Pass, including all existing extended steps. | `agent-pr-check.log`, `gate-steps/` |
| Bootstrap and cold comparisons | All 302 C/H files match across bootstrap/stages 0/1; all 430 cold C/H/.xi files match stage 1. | `agent-pr-check.log`, `gate-steps/proof-cold-collection.log` |
| Unit suites | 1,045 pass, zero failures/skips, 27,250 assertions. This includes the existing signaling-NaN promotion test and scalar/Var boundary coverage. | `gate-steps/verify.log` |
| Compiler fixtures | 1,288 pass, 2,848 checked artifacts. | `gate-steps/verify.log` |
| Documentation and commands | 119 executable examples match; all command checks pass, including REPL loading, inspection, and reload. | `gate-steps/` |

The generated review accounts for four bootstrap files: private scalar
parameter names and two diagnostic source-line updates in `common.c`, the
same parameter names in `common.h`, and the common source hash in `collect.c`
and `linked-meta.c`. The generated API page changes only source-line
references. No generated file was edited by hand. No new test requirement,
compiler operation, registry, or compatibility wrapper was added.

The signature-comparison scratch script initially tried to put absent
optional metadata into a List. Selecting only present metadata fixed that
probe; `signatures-initial.log` retains its failure. A preliminary whole-C
comparison also exposed the expected diagnostic line-number changes; the
final comparison accounts for them separately from the scalar methods.
Neither result required a production correction.

The source hash stayed unchanged during validation. Package suites were not
repeated for this scalar-only follow-up; their pre-scalar results are below.
Performance remains unmeasured. Retain this result locally and keep
target/signature generation and all other harder cases deferred. No push,
PR, or integration enrollment is authorized.

Fresh checks pass on this integrated tree. Earlier PR #285-base checks below
remain historical. Logs live under `debug/dev-reassessment/`.

| Current integrated-tree check | Result | Log |
| --- | --- | --- |
| `make build-safe`; `make doc-generate` | Pass with current dev bootstrap and authoritative generated output. | `build-safe.log`, `doc-generate.log` |
| Full `make agent-pr-check` | Pass, including all five existing extended steps. | `agent-pr-check.log`, `gate-steps/` |
| Bootstrap/stage comparisons | Bootstrap == stage 0 == stage 1, all 302 C/H files. | `agent-pr-check.log` |
| Cold collection | All 430 C/H/.xi files match stage 1. | `gate-steps/proof-cold-collection.log` |
| Unit suites | 1,045 pass, zero failures/skips, 27,250 assertions; standalone thread suite also passes. | `gate-steps/verify.log` |
| Compiler fixtures | 1,288 pass, 2,848 checked artifacts, including new with/alias/unalias fixtures. | `gate-steps/verify.log` |
| Documentation and commands | All checks pass; 119 executable documentation examples match. REPL and graph checks pass. | `gate-steps/` |
| Autodiff, libcurl, libuv | All 126 package tests pass; autodiff's ten compiler fixtures and both examples also pass. Existing dependency prefixes reused. | `autodiff.log`, `libcurl.log`, `libuv.log` |
| Focused reader/native/precedence/Mutex/indent probes | Pass; fresh reader works without a session, shipped native dispatch leaves it null, both call syntaxes retain `4 4 99 99` precedence. | `focused-probes.log` |
| Embedding dependency probe | Edited payload changes generated C and remains in its depfile. | `embedding-dependencies.log` |
| Scalar forwarding prototype | Nine finite scalar cases pass; candidate only, no production edit. | `scalar-feasibility.log` |

The initial scratch build invocations omitted the compiler C-header search
directory and the provider source input, respectively. Correcting those
invocations made the probes pass without source changes. Their initial logs
remain as `focused-probes-initial.log` and
`focused-probes-provider-input.log`.

Authored source hashes stayed unchanged during validation. The full Make
target is local correctness evidence; no publication receipt is claimed.
Performance measurements and publication remain unattempted. The private
delivery context remains active. This table records the pre-scalar tree;
the follow-up's validation is recorded separately above.
All other deferred cases below remain deferred; no new registry, public
compiler query, module extraction, or REPL redesign is selected.

The generated review distinguishes the independent patch from upstream
refresh work. Reader, cache, native-call, and linked hash deltas follow this
patch. Current dev's authored `unalias` support additionally regenerates
`macros.c`, `statements.c`, `symtab.c/.h`, the module catalog, and API/llms
output. For example, current dev's `src/symtab/bindings.x` already defines
`Sym.undefine_alias`, while its checked-in bootstrap header lacks that
prototype. The ordinary regeneration emits it; no bootstrap file is edited
by hand. Both source and generated changes are reviewed against fetched dev.

## Original reconciliation with PR #285

The inspected PR head is `5f7274f978b7749e5d2d9cad1b218ea99277ea2b`,
one source-only commit based on the same `9e68d6b` as this workspace. At
inspection it is open and unmerged; its body records a shared-integrator
submission. Its seven-file diff removes nine Lisp forms and nine autodiff
placeholders.
Treat that authored change as the predecessor regardless of merge order.
Its readiness metadata does not authorize this workspace to submit or push.

| Area | PR #285 | Local reconciliation |
| --- | --- | --- |
| Source embedding | Same five conversions across `src/macros/lisp.x`, `lib/lisp/lisp.x`, and `commands/repl/repl-runtime.x`. | Keep the PR's conversions. They disappear from this batch's residual diff. |
| REPL include | PR needs no added include; `lib/lisp/lisp.x` already includes `meta.x`. | Drop this batch's extra `#include "meta.x"` when replaying. No REPL implementation change remains here. |
| Lisp module comment | PR changes only its embedding wrapper. | Keep the separate local comment explaining session-free reader prefixes. |
| `$lock` | Replaces the Lisp-built type with ordinary `Mutex` syntax. | Accept it. The previous blanket deferral of early built-ins was too broad. |
| libcurl / libuv | Uses existing meta operations for captured text and identifier construction. | Remove these conversions from the deferred backlog. No competing package edits. |
| Autodiff | Deletes the nine placeholder Lisp definitions; real meta definitions remain. | Remove placeholder investigation from the backlog. Keep native meta algorithms. |
| Data reader and reader-only consumers | No changes. | Retain the independent local change, its prefix/lifetime test, and the bounded tokenizer-mode repair needed to check `indent-convert`. |
| Linked native calls | No changes to lookup, context, or session initialization. | Retain lazy initialization at ordinary lookup; preserve the existing shipped direct-selection path and all binding precedence rules. |
| Generated files | PR intentionally omits final bootstrap artifacts. | Regenerate for the eventual combined tree. Do not reuse artifacts or proof from either separate tree. |

The PR changes no binding-resolution owner. Its native calls continue through
the current explicit meta-call path; this batch leaves ordinary environment
lookup and `Lisp.apply` intact. The libuv calls use the existing nested-call
path and `Code.binding_spelling`, which accepts a one-String type List. There
is no conflicting new namespace or prototype policy to choose between.

A three-way content merge using `9e68d6b`, the pinned PR head, and the local
working files succeeds for every PR-touched file. This test wrote only
temporary files; it did not change HEAD, the index, or source files. The
machine-readable results are `debug/pr285-reconcile.json`. In particular,
`src/macros/lisp.x` already equals the PR file, and the other two overlapping
files contain the identical embedding substitutions plus the small local
include/comment differences described above.

The reconciled residual source patch is `debug/pr285-residual.patch`, with
its file list in `debug/pr285-residual-files.json`. It excludes the five
duplicate conversions, the extra REPL include, this plan, and the generated
API documentation. `git apply --check` succeeds against a temporary copy of
its files from the pinned PR revision. The patch has now been applied to
this workspace. Documentation and bootstrap outputs are regenerated from
the combined tree, rather than copied from the separate work.

The `$lock` distinction was also probed: a `--plain` source defines the
PR-style `Mutex` decorator before including `mutex.x`. It compiles and runs,
evaluates its operand once, and releases the mutex. See
`debug/pr285-early-lock-build.log` and `debug/pr285-early-lock.log`. This
checks ordinary type syntax before its declaration, not a native query before
its prototype. The latter bootstrap problem remains deferred.

### Reconciled replay and validation sequence

1. Preserve the current local work and its evidence. The source-only patch
   and prior plan are saved as `debug/pr285-local-source-before.patch` and
   `debug/pr285-plan-before.md`. The complete pre-replay working tree is also
   preserved in the Git stash named by
   `debug/combined-pr285/recovery-stash.txt`.
2. Use the inspected PR revision, or its eventual integrated successor, as
   the local implementation base. If that revision changes, compare the new
   diff before replaying. Do not infer succession from a moving branch name.
3. Replay only the reader, reader-client, cache-ownership, lazy-session, test,
   and related documentation changes. Omit `src/macros/lisp.x` and
   `commands/repl/repl-runtime.x` from the residual patch. In
   `lib/lisp/lisp.x`, retain only the reader ownership comment.
4. Regenerate documentation and any required bootstrap artifacts through the
   existing targets on the combined source. The PR notes an initial embedded
   built-in source-offset difference before convergence; investigate actual
   differences rather than copying either tree's generated files.
5. Verify the combined tree locally: self-host and cold interface parity;
   session-free reader and linked-call probes; binding-order and embedding
   fixtures; helper/native-module behavior; Mutex/early-template behavior;
   REPL and graph checks. Run the existing autodiff, libcurl, and libuv checks
   for their changed clients where configured dependencies are available.
   Finish with authored/generated diff review. Add no new recurring gate.
6. Record this as combined local evidence. Any PR, readiness enrollment, or
   push still requires Gary's explicit approval for this workspace.

The source replay is complete. A fresh `make build-safe` passed on the
combined source. PR #285 is now merged, but its head remains the inspected
`5f7274f`; this local branch deliberately uses that pinned source revision.
The prior local checks below establish the pre-PR batch only. New combined
results are recorded separately under `debug/combined-pr285/`. The PR's own
reported package and gate results do not substitute for these checks.

## Binding precedence decision

Preserve current behavior for both `$name(...)` and `$(name ...)`:

1. Visible source macros retain precedence over native meta calls.
2. Includes install their advertised meta provider at their source position.
3. Subsequent ordinary lookup retains a later unit-local Lisp definition.
4. Compiler-shipped translators keep their existing linked-callee selection.
5. Bodyless native declarations retain signature certification, built-in
   target precedence, selected-module order, and duplicate-supplier warnings.
6. Shared inherited definitions remain final to Lisp `def`; host bindings
   retain their existing ability to shadow inherited bindings in a child.

The current Lisp environment remains authoritative for these bindings. Moving
native invocation out of it is deferred until one owner can preserve these
rules, interpreted callbacks, and session lifetime without mirrored state.
Do not bypass the environment just because a native function of that name
exists. `src/meta-native/functions.x` explicitly preserves later definitions;
`ordinary-interface-meta-order-warm` records the include/redefinition order.

## Early bootstrap decision

Accept PR #285's ordinary `Mutex` spelling in `$lock`. Current dev replaces
`$let` with `with`; its native `_with_assignment` now asks `Code.type`
directly, while the early decorator still calls it through Lisp
`with.expand`. Keep that wrapper, the other early native-call wrappers in
`etc/builtin-macros.x`, and the low-level SymbolSet generators in
`lib/var-tags.x`. Scalar forwarding in `lib/common.x` now uses ordinary
macro code with no Lisp escapes. Built-ins load before `lib/meta.x`
declarations; introducing `$Code.type` there would not preserve
that ordering. Do not add parser exceptions, synthesized prototypes, another
macro execution engine, or new public compiler queries to force this change.

Convert text embedding only where `meta.x` declarations are already visible.
The compiler macro module includes `meta.x`; runtime Lisp includes it before
its member definitions and already exports it to the REPL runtime. Keep
ordinary `x2c_embed_text` dependency tracking, source-relative paths, and
String materialization. Check these conversions with the existing seed
before adopting them, then build through the next stage.

The existing seed can compile session-free reader calls. Rebuild that reader
before adopting callers that no longer create sessions. Generated bootstrap
C/H must come from repository targets, never hand edits.

## Original local implementation

This records the already-authored batch. The reconciliation sequence above
owns the residual scope and removes the duplicated step 5 conversions.

1. Make reader prefixes intern their own names with `Atom.intern`, instead
   of reading globals initialized by `Lisp.kernel`. Keep `Lisp.read`'s
   signature, tokenizer, cursor/error behavior, and caller-owned results.
   Add a first-in-suite test for all four prefixes without a session, with
   nested Context lifetime coverage. Reuse existing reader parity tests.
2. Remove the interface reader session. Initialize `source_hashes` and
   `linked_providers` under the existing process cache owner, and clear them
   in its existing shutdown. Remove the helper's unused `Lisp.kernel` call.
3. Remove reader-only sessions from `tools/definitions.x`,
   `tools/indent-convert`, `commands/graph/x2c-graph.x`, and the expression-body
   AST comparison script. Continue using the full reader grammar through
   `Lisp.read(NULL, ...)`; do not substitute a narrower reader.
   The unchanged `indent-convert` baseline fails C compilation because its
   `Tokenizer.new` call omits the required mode. Supply the existing `<x2c>`
   mode as a bounded prerequisite; defer the tool if further drift appears.
4. Move native call session initialization into `_meta_function`, the existing
   ordinary name lookup owner. Keep `_shipped_callee` and its already-direct
   `Func` application unchanged. Native value entry and named application
   should not create a session when shipped selection answers them. Keep
   declaration effects before native argument evaluation. A fresh compiler
   API probe calling linked `native_scalar_types` records the before/after
   session allocation; ordinary binding and callback tests check the fallback.
5. Replace Lisp literal/embedding wrappers in `src/macros/lisp.x`,
   `lib/lisp/lisp.x`, and `commands/repl/repl-runtime.x` with the existing
   native `x2c_embed_text` operation. Preserve runtime-loaded Lisp contents.
6. Review the authored diff for duplicated ownership and accidental semantic
   changes. Verify the local self-host transition, relevant existing tests,
   reader clients, and REPL behavior. Record results and remaining work here.

## Deferred cases and reasons

| Case | Concrete remaining work | Why deferred |
| --- | --- | --- |
| General native callable dispatch | Separate ordinary native storage/application from the session while preserving the precedence above and native callback context. | This batch only removes initialization before the existing shipped direct path. A second Map would duplicate ownership; extending direct `Func.apply` can lose active-session behavior. |
| Remaining early built-ins | Make existing native compiler operations available before public meta declarations. PR #285 removes `$lock`'s type-only Lisp expression; current dev replaces `$let` with the still-Lisp-backed `with.expand`. | Native calls need a coherent bootstrap design; plain type syntax does not have that dependency. |
| Native `bind` evaluation | Reuse the runtime's existing native lookup, including callback adapters, directly. | Lookup is private to the Lisp module; a compiler-only duplicate would change target precedence. |
| Optional iterator destination | Replace `C.iterator.call` with a native adapter preserving explicit and omitted destinations. | Coupled to callable signatures, callback adaptation, and storage lifetime. |
| Deferred class recipes | Change callable dispatch for defaults, initializers, and field writers. | Native producers already exist; preserve their delayed execution and source visibility. |
| Native target/signature generation | Migrate generated module entries, linked-meta hashes, callback tables, private SDK queries, and SymbolSet construction under their existing owners. Scalar forwarding and the two compiler-owned inventory signature wrappers are completed separately above. Leave public `$lisp.bind` unchanged. | Some queries have no x2c declaration or run before declarations are available. The native algorithms already exist; access and bootstrap order remain the obstacle. |
| Generic scalar access | Move `NativeScalarAccess` out of the Lisp module while retaining its existing users and ABI. | Ownership cleanup requires connected header/source work, not an evaluator replacement. |
| Full reader extraction | Give the shared grammar a module independent of the Lisp implementation. | The selected change removes session construction; it deliberately retains `Lisp.read` and its existing ABI. |
| Home discovery | Replace the `etc/compiler-sdk.xlisp` installation marker if that file ceases to be mandatory. | The compiler still needs that file after this batch. |
| Other optional-package Lisp | Inspect only uses beyond the libuv/libcurl conversions and autodiff placeholder deletion already owned by PR #285. | Do not repeat completed predecessor work. Runtime package Lisp installation APIs remain supported. |

Keep Lisp imports, definitions, lexical closures, queued effects, budgets,
callback truth semantics, and runtime package installation APIs. Keep the
REPL's lowerer, interpreter storage, native functions, interruption, and
recovery behavior. No REPL redesign is selected.

## Validation and delivery

Use local stage builds and existing checks appropriate to this batch:
selected Lisp/Atom/Var suites; compiler fixtures for binding order, native
meta, macro slots and embedding; helper transport; cold interface parity;
graph and REPL checks; and generated documentation checks. Add no recurring
gate or reordered readiness step. Record actual commands and failures.

Check reader operation in a fresh executable before any session exists;
unit-suite order alone does not prove that premise. Test prefix spelling and
results surviving an inner Context after explicit ownership promotion.
Native embedding must still record source dependencies and track file edits.

Refresh affected generated files only through documented targets. Preserve a
usable local bootstrap if regeneration is needed for the transition. No
publication gate is required merely for a private checkpoint; do not push,
open a PR, enroll with an integrator, or advance `dev` or `main`.

## Combined local result

The independent patch is replayed on PR #285's pinned head
`5f7274f978b7749e5d2d9cad1b218ea99277ea2b`. The branch is
`codex/lisp-independence-pr285`. Changes remain uncommitted and local;
the pre-replay snapshot remains recoverable from the recorded stash.

The following predecessor files have no further authored changes:
`commands/repl/repl-runtime.x`, `src/macros/lisp.x`,
`etc/builtin-macros.x`, and the three changed package sources. The only
additional edit in `lib/lisp/lisp.x` is the reader ownership comment.
No deferred compiler facility was redesigned.

Combined results are preserved under `debug/combined-pr285/`:

| Check | Result | Evidence |
| --- | --- | --- |
| Fresh `make build-safe` | Pass. | `build-safe.log` |
| Full `make agent-pr-check` | Pass, including its existing bootstrap, test, documentation, and command checks. | `agent-pr-check.log`, `gate-steps/` |
| Bootstrap, stage 0, stage 1 | Both comparisons match all 302 C/H files. | `agent-pr-check.log` |
| Cold collection | All 430 C/H/.xi files match stage 1. | `gate-steps/proof-cold-collection.log` |
| Unit suites | 1,045 passed, zero failures/skips, 27,250 assertions. The standalone thread run also passes. | `gate-steps/verify.log` |
| Compiler fixtures | 1,262 passed, 2,798 checked artifacts. | `gate-steps/verify.log` |
| Documentation | Audit passes; all 111 executable examples match output. | `gate-steps/doc-check.log`, `gate-steps/doc-outputs.log` |
| Command checks | Pass, including graph, REPL API/interruption, inspection, reload, and source loading. | `gate-steps/commands-check.log` |
| `make -C packages/autodiff check` | 16 tests, 94 assertions, ten compiler fixtures, and both examples pass. | `autodiff.log` |
| `make -C packages/libcurl test` | 31 tests, 219 assertions pass. | `libcurl.log` |
| `make -C packages/libuv test` | 79 tests, 837 assertions pass. | `libuv.log` |
| Native module probes | Pass. | `native-modules.log` |
| Fresh reader / native dispatch / precedence / early Mutex / indent probes | Pass. Reader construction needs no session; linked native dispatch leaves `macro_lisp` null; precedence remains `4 4 99 99`. | `focused-probes.log` |
| Native embedding dependencies | Changed input changes embedded C; the input path remains in the dependency file. | `embedding-dependencies.log` |

The cached curl and libuv dependency receipts were verified and reused. No
new dependency installation or toolchain change was required. The source
review found no concrete issue in canonical lifetime, cache ownership,
ordinary binding precedence, shipped dispatch, or active-session callbacks.

The first full-check attempt stopped at bootstrap comparison. Its only
C/H difference was `parse.c`'s embedded built-in source offset changing from
1421 to 1411: exactly the ten bytes removed by PR #285's `Mutex` spelling.
The second ordinary regeneration converged. The initial log and exact diff
remain as `agent-pr-check-first-pass.log` and
`first-parse-stage-diff.patch`; bootstrap files were never hand-edited.

The generated diff was reviewed. Six bootstrap C files change: reader
prefix interning and literal indexes; removal of the interface session and
its cleanup; source dependency hashes; embedded PR #285 built-ins and their
source offset; and the lazy native-call initialization. The three generated
API pages contain only the reader contract correction and source-line
updates. No generated file was copied from the earlier separate tree.

`evidence.json` records the commands, counts, base, branch, and authored
source hashes. Those hashes stayed unchanged during validation. All tougher
cases in the table above remain deferred. Performance measurements and
publication were not attempted. The private delivery context remains active;
the full Make target was run solely as local validation.

## Local result and evidence

This section records validation before the replay onto PR #285. The
original pre-PR batch is retained in the recovery stash, not the current
working tree. The combined results above supersede these earlier limits.
Canonical Lists, runtime Lisp signatures, the REPL execution model, native
target precedence, and early built-in wrappers remain in that snapshot. General
compilation still preloads the shared Lisp library. Full evaluator removal,
the deferred rows above, optional package checks, and performance measurements
were not attempted at that point. No publication gate, bootstrap refresh,
push, or PR ran during that earlier validation.
The unchanged shipped seed builds the authored sources; stage 0 and stage 1
converge, so this batch needs no new bootstrap capability.

Observed changes:

- A fresh executable's `Lisp.read(NULL, "'(x)", ...)` failed its prefix
  assertion before the change and succeeds afterward. The added unit case
  checks all four prefixes and promotion out of an isolated Context.
- A fresh compiler API probe selects linked `native_scalar_types` from a
  shipped definition context. It returns a nonempty native table in both
  versions. `compiler.macro_lisp != NULL` changes from 1 to 0.
- A provider/redefinition probe calls the same name through `$name(...)`
  and `$(name ...)`. Both return 4 after the include and 99 after the later
  Lisp definition: `4 4 99 99`.
- Native embedding records `payload.txt` in the dependency file. Editing
  that file changes the embedded generated-C contents on the next translation.
- Interface reading and provider hashing now use the existing process cache
  owner; the separate interface session and shutdown hook are gone.

| Check | Result | Local log |
| --- | --- | --- |
| `make build-safe`, followed by scoped `make build` runs | Pass; seed accepts the changed source. | `debug/bootstrap.log`, `debug/lisp-independence-native-build.log` |
| `make stage-1`, `make stage-diff-1` on final compiler source | Pass; 302 C/H files match. | `debug/lisp-independence-final-stage1.log` |
| `make proof-cold-collection` on final compiler source | Pass; 430 C/H/.xi files match. | `debug/lisp-independence-final-cold.log` |
| `make -C unittest test-all`; selected Lisp, Atom, Var suites | 152 passed, 2,035 assertions. | `debug/lisp-independence-unit.log` |
| Fresh `./test-all lisp_suite` | 92 passed, 1,032 assertions; session-free prefix case runs first. | `debug/lisp-independence-lisp-fresh.log` |
| 15 selected compiler fixtures | Pass; binding order, Lisp slots/effects, native results, and embedding. | `debug/lisp-independence-fixtures-retry.log` |
| Helper lifecycle and transport probes | Pass; crashes, deadlines, restart, and framed data. | `debug/lisp-independence-helper.log`, `debug/lisp-independence-transport.log` |
| Native module probes | Pass; existing selection, signature, and package-module behavior. | `debug/lisp-independence-native-modules.log` |
| `make commands`; `sh commands/graph/tests/run.sh` | Pass, including graph contract reading. | `debug/lisp-independence-commands-build.log`, `debug/lisp-independence-graph.log` |
| `sh commands/repl/tests/run.sh` | Pass; includes API, interruption, inspection, reload, and source-load checks. | `debug/lisp-independence-repl.log` |
| Expression-body probes | AST, generated C/H, and runtime parity pass. | `debug/lisp-independence-expression-bodies.log` |
| `indent-convert --check` on an inert scratch file | Pass; tool proves converted AST parity. | `debug/lisp-independence-indent-retry.log` |
| Native dispatch, precedence, and embedding probes | Pass with observations above. | `debug/native-dispatch-after.log`, `debug/lisp-independence-binding.log`, `debug/lisp-independence-embedding.log` |
| `make doc-generate`, `make doc-check` | Pass; generated API prose and source links refreshed. | `debug/lisp-independence-final-doc-generate.log`, `debug/lisp-independence-final-doc-check.log` |

An initial fixture attempt overlapped a build that deletes and recreates
header symlinks; C compilation reported missing `x2c.h`. After the builds
finished, all 15 selected fixtures passed without changing expectations.
The original log is `debug/lisp-independence-fixtures.log`. Non-executable
command test scripts were rerun through `sh`. The REPL script already runs
its source-load suite; an accidentally queued duplicate was stopped after
the complete first run passed.

The unchanged `indent-convert` script separately reproduced the tokenizer
constructor arity error. The only prerequisite repair supplies `<x2c>`;
baseline and repaired logs are `debug/lisp-independence-indent-baseline.log`
and `debug/lisp-independence-indent-retry.log`.

The completed authored diff was reviewed. The final review removed a
redundant `_process_cache()` call from pure record decoding: both cache
entry paths already initialize that owner. Final stage and cold comparisons
were rerun afterward. No new synchronization, cache, registry, or diagnostic
was added. The generated documentation changes contain the reader contract
correction and source-line updates.

## Plan review

- `Atom.intern` and canonical pools already establish name identity and
  lifetime. Reader consumers need no session, extra once-state, or new lock.
- The process cache already owns the interface maps. Reuse its initialization
  and shutdown instead of keeping a session-shaped owner for those maps.
- `x2c_embed_text` already resolves paths, records dependencies, and returns a
  String. Use normal native meta insertion instead of rebuilding literal ASTs.
- Keep the existing Lisp binding owner, native signature checks, macro binder,
  and early wrapper ordering. No new registry, representation, traversal,
  cache, validator, diagnostic, or negative fixture is proposed.
- `_shipped_callee` already establishes selection of a compiler-linked Func
  and `_apply_linked` already calls it without activating Lisp. Move session
  initialization to the fallback that actually reads session bindings; do
  not extend the direct path to ordinary user or callback callables.
- The positive reader regression covers the newly supported session-free
  call and canonical lifetime. Existing parity, integration, and REPL checks
  cover preserved behavior; they do not become new process requirements.
