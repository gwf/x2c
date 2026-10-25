# Compiler independence from Lisp

> Status: active
> Local work authorized by Gary on 2026-10-24, starting at `9e68d6b`.
> Preserve canonical Lists, the REPL, and runtime Lisp. No pushes or PRs.
> Reconciled with predecessor PR #285 at `5f7274f978b7749e5d2d9cad1b218ea99277ea2b`.
> Gary authorized local replay and combined validation on 2026-10-24.
> The independent source changes are replayed on `5f7274f` in
> `codex/lisp-independence-pr285`; combined local validation passed.
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

## Reconciliation with PR #285

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

Accept PR #285's ordinary `Mutex` spelling in `$lock`. Keep the remaining
early native-call wrappers in `etc/builtin-macros.x` and the low-level
generators in `lib/common.x` and `lib/var-tags.x`. Built-ins load before
`lib/meta.x` declarations; introducing `$Code.type` there would not preserve
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
| Remaining early built-ins | Make existing native compiler operations available before public meta declarations. PR #285 already removes `$lock`'s type-only Lisp expression. | Native calls need a coherent bootstrap design; plain type syntax does not have that dependency. |
| Native `bind` evaluation | Reuse the runtime's existing native lookup, including callback adapters, directly. | Lookup is private to the Lisp module; a compiler-only duplicate would change target precedence. |
| Optional iterator destination | Replace `C.iterator.call` with a native adapter preserving explicit and omitted destinations. | Coupled to callable signatures, callback adaptation, and storage lifetime. |
| Deferred class recipes | Change callable dispatch for defaults, initializers, and field writers. | Native producers already exist; preserve their delayed execution and source visibility. |
| Native target/signature generation | Migrate generated module entries, linked-meta signatures/hashes, callback tables, private SDK queries, scalar argument splices, and SymbolSet construction together. | Some queries have no x2c declaration or run before declarations are available. |
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
