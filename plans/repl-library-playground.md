> Status: active
> Design decisions selected with Gary on 2026-10-29. Implementation authorized
> and started on 2026-10-29; verification and delivery remain pending.
> Baseline: `804275488c99169294a593bf660f1e178abec70c`.

# REPL library playground

## Result

Make the command-line REPL a place to learn and exercise a C or x2c library:
load its API, discover operations, create objects, call functions and methods,
inspect results, and repeat. Ordinary library code needs no `meta` annotations,
REPL wrappers, generated package, or serialization contract.

The defining example is a C library with a header declaring `Point`,
`point_new`, `point_move`, and `point_free`. The user must be able to do this:

```text
:load "points.c"
:symbols point
:info point_move
:source point_move
Point *p = point_new(1, 2);
point_move(p, 5);
:inspect *p
p->x;
point_free(p);
p = NULL;
```

The same object must survive across submissions. `:inspect *p` displays its
type and fields, and `p->x` returns `6`. A function returning `Point` by value
must also work. The same create-call-inspect workflow must work with a header
and an already compiled library. For an opaque handle, inspect its declared
type and related operations, then use library queries instead of private fields.

This is the native command-line playground. The independent
[browser playground](browser-playground.md) remains outside this plan.

## Selected design

Gary selected these choices during planning:

1. **One worker owns all live execution.** Prompt variables, loaded globals,
   library allocations, prompt functions, callbacks, and native modules share
   one native address space. A terminal supervisor owns editing and history.
2. **Compile every executable submission.** Use ordinary x2c parsing,
   binding, typing, transformation, native compilation, and calling
   conventions. Replace the REPL's manual Lisp execution path. Keep the shared
   Lisp library and explicit Lisp use unchanged.
3. **A successful load or reload starts a fresh session.** Clear prompt
   variables, functions, types, and library state together. Keep terminal
   history, the transcript, and load configuration. Do not migrate objects
   or replay effectful input automatically.
4. **Top-level cleanup has session lifetime.** Persistent managed declarations
   and direct top-level `defer` survive submission boundaries. Explicit blocks
   and function calls keep normal cleanup. Forced worker death cannot
   guarantee cleanup.

These choices supersede the playground-relevant parts of
[compiled prompt functions](archive/repl-compiled-prompt-functions.md) and
[the shared helper](archive/repl-shared-helper.md): interpreted top-level
execution, independent-data transport, and preservation of prompt values
across library replacement. Those plans correctly record their earlier scope.

### Alternatives considered

| Alternative | Consequence | Decision |
| --- | --- | --- |
| Extend the helper with remote object handles | Needs remote field/address operations, alias rules, callback reentry, and lifetime rules for pointers held by prompt code. | Do not introduce a second C object model. |
| Keep hybrid interpreted and native execution in one worker | Removes transport failures but retains separate layout, call, and expression behavior. | Replace manual Lisp lowering with native submissions. |
| Run unified native code in the terminal process | Uses ordinary objects, but an assertion or bad pointer loses the terminal client and history. | Put execution in the worker. |
| Retain old code or migrate objects during reload | Requires rules for old pointers, new globals, destructors, and external resources. | Start fresh after successful rebuild. |

## User-facing commands

Retain semicolons, multiline submissions, bracketed paste, contextual
completion, and colon commands on separate lines. Inspection commands preserve
pending incomplete source. Both interactive and piped input use the same
submission grammar.

| Command | Defined behavior |
| --- | --- |
| `:help [COMMAND]` | Group commands by exploring, loading, inspecting, and controlling a session. Include one small create-call-inspect walkthrough and the restart rule. |
| `:symbols [PREFIX]` | Readable rows with kind, authored name, signature/type, and origin for prompt and selected library APIs. Keep prefix filtering. |
| `:symbols --all [PREFIX]` | Include the remaining visible runtime and dependency names. |
| `:symbols --kind KIND --file "PATH" [PREFIX]` | Optional, composable filters over the same symbol rows. |
| `:info NAME_OR_EXPRESSION` | Show the resolved type without executing the expression. Functions include named parameters, return type, declaration/definition locations, and available adjacent documentation. Types include fields, qualifiers, and methods. |
| `:source NAME` | Show the captured authored definition, with its path and lines. Fall back to the declaration when only a header is available, and say that the definition is unavailable. |
| `:members TYPE_OR_EXPRESSION` | List fields, applicable methods, and related C functions with signatures. Resolve the receiver's type without evaluating it. Use ordinary member and delegate resolution. |
| `:inspect [--depth N] [--limit N] EXPRESSION` | Evaluate once and display a bounded view of the typed result. |
| `:files` | List explicit roots, resolved paths, and build configuration. Distinguish selected APIs from supporting dependencies. |
| `:load "PATH" ...` | Build the complete candidate root set and replace the live session only on success. Accept source and header roots. Adding roots also starts fresh. |
| `:reload` | Rebuild the current root set from current files and start fresh on success. |
| `:reset` | Start a fresh worker using the last successful program artifact and its retained declarations. Do not rebuild edited sources or replay prompt input. A changed external native dependency requires `:reload`. |
| `:save "PATH"` | Save a replayable `.repl` transcript and resolved launch/load configuration. This records instructions, not heap state. |
| `:replay "PATH"` | Explicitly start a fresh configured session and run that transcript in order. Stop at the first failure. |
| `:cancel`, `:quit`, `:stats [verbose]` | Keep input cancellation, exit, and accurately scoped runtime statistics. |

`--kind` and `--file` also work individually. All command arguments receive
relevant completion: paths for load/save/replay, visible names for source/info,
types and receivers for members, and filter values for symbols. Use the same
symbol/member query for browsing and completion. Completion lists signatures
for callables; it does not make the user decode emitted underscore spellings.
Both `Type.method` and its actual declared C spelling resolve through the
compiler where they denote the same binding. Do not invent textual aliases.
For a C type, separately list visible functions whose declared parameter or
result types refer to that type, including pointer and out-parameter forms.
Use normalized declared type identity rather than every operation accepting
`void *`. Show the real function name and argument position. This is discovery,
not an invented method wrapper: `sqlite3_close(db)` remains that C call.

Keep `:ast` for typed syntax inspection. Retain `:lowered` as an explanatory
compatibility command that reports native execution; do not fabricate Lisp.
Update `--dump` to identify the native submission and its generated artifacts.
The ordinary help leads with library work rather than ASTs or allocation data.

## Source and discovery

The compiler remains the owner of bindings, types, member resolution, and
source ranges. Add a compact session-owned description of successfully
published bindings: origin, authored spelling, parameter labels, source range,
source snapshot, and optional adjacent documentation. Keep parameter labels
out of canonical signature identity and the runtime ABI.

Reuse `Compiler.definition_rows`, source declaration/range operations, and
`SourceView`. The LSP already uses these producers. Do not run an LSP server or
create a second source parser. Current `ReplSession.new` explicitly rejects
`source_facts` because those maps can retain submission scratch; do not simply
remove that check. Export the required immutable description while its source
owner is alive, then commit it with the corresponding binding.

Source lookup shows the snapshot used to build the running code. Editing a
file does not silently change `:source`; a successful reload updates it.
Retain the committed source descriptions, preprocessing state, and native
declaration inputs with the program artifact. A reset restores that bundle.
Later submission compilation also uses the retained headers/declaration
inputs; reading edited live headers would silently change the running ABI.
Use dependency-scoped build inputs and existing preprocessing outputs, not a
snapshot of the user's installation or workspace.
Prompt definitions retain their submitted text. Header-only functions show
their declaration and comments, never an invented implementation. Preserve
macro spelling and source locations where the ordinary compiler supplies
them; say when an exact authored range is unavailable. No decompiler is needed.

All ordinarily visible declarations remain usable. Default browsing emphasizes
prompt definitions and explicitly selected source/header APIs; `--all` exposes
dependency and runtime names. Required public types accompany the selected
API. Static implementation details retain C privacy. Enumerator constants and
ordinary C header macros remain available through normal preprocessing.
List macros as macros without evaluating arbitrary expansions during browsing.
Use the existing preprocessor's macro tables, not regexes over headers or a
second conditional-compilation evaluator.

## Loading ordinary libraries

Support both ways developers already obtain C libraries:

- Source roots, with normal headers, includes, cross-file prototypes, globals,
  and native dependencies.
- Header roots plus matching object files, static archives, or shared
  libraries. Declaration-only functions become callable through their real
  native symbols. Source text is optional for execution, not for declarations.

Reuse the ordinary `CliRequest`, project resolver, dependency handling, native
toolchain, and artifact cache. Expose the relevant existing build options in
`x2c repl`: include directories, defines, C/link flags, native objects and
libraries, package directories, and explicit manifest/target/profile selection.
Use the existing spellings and path rules. A selected manifest supplies its
target's sources and dependencies; the REPL supplies its own executable entry.
Do not infer installation, run a package installer, or invent a REPL manifest.

For direct library use, accept source/header/native input operands at startup,
and allow `:load` to add source/header roots to that configuration. Native input
operands and link flags are configured at launch; changing them means a fresh
launch or replay. Resolve the full startup set in one build. An empty launch
continues to start a usable prompt.

Build one program module for the selected root set. Reuse ordinary per-unit
translation and linking, provider ownership, generated headers, module shape,
and exported target construction. Do not concatenate source files or relink
every earlier submission for a new expression. The worker loads the program
module and later submission modules against its one x2c runtime.
Supply typed native function/global addresses to submission modules, or
explicitly link their references to that selected program module. The current
`Func` target table and `RTLD_LOCAL` loader do not automatically expose raw C
symbols. Reuse native ABI emission without imposing compile-time `meta`
lifetime summaries on ordinary library calls.

Original C headers, their preprocessing configuration, and the program's
generated declaration headers reach submission compilation. The host C
compiler owns sizes, alignment, field access, bitfields, calling conventions,
and struct returns. Do not reconstruct attributed or packed header types from
the collector's reduced field rows. Extend staged compilation's explicit
configuration rather than changing global meta toolchain state for REPL work.

Retain the current `main` convenience adapter and single-program selection:
no-argument main remains `main()`, and argc/argv main accepts an Array of
Strings. Its implementation keeps ordinary native semantics. Loading another
main-bearing source replaces that program root as today; the successful
replacement now clears prompt state too. Other conflicting definitions fail
under ordinary linkage rules.

### Replacement and failure

Prepare the candidate program and a fresh worker while the old worker remains
usable. Publish the new configuration only after build, load, and worker
initialization succeed. A rejected candidate preserves the entire previous
session. Retain the exact last successful artifact for `:reset`, independently
of mutable build-cache paths.
Keep its committed declaration/source bundle and native dependency identities
with it. Before starting a fresh worker, use the existing artifact-dependency
checks for explicitly selected external libraries. If a shared library at a
recorded path has changed, `:reset` refuses and requests `:reload`; it must not
load new binary code against old declarations. Preserve the active worker
when one exists. After a crash, keep the terminal available for reload even
when the previous native program cannot restart. Ordinary system-runtime
dependency handling stays unchanged.

On success, report explicitly that all prompt and library state was cleared,
then switch workers and retire the old worker. Do not preserve native values,
saved functions, or apparent addresses across replacement. Existing
signature/layout compatibility checks against the old session become
unnecessary; the new session can accept changed signatures and types.

Compilation failure is atomic for session publication. Library constructors,
file writes, or other external effects during candidate initialization are
not transactional and cannot be undone. Keep that distinction in diagnostics.

## Native submissions and object lifetime

Use `Compiler.parse_submission` and semantic transactions for incomplete input,
binding, and publication. Form canonical ASTs with Match and literal templates;
use ordinary resolution, initialization, cleanup, transformation, and emission.
Adapt the current native staging entry to compile one complete submission.
Accept ordinary C type and storage declarations through those owners,
including enum/union declarations, qualifiers, and function-local static
storage. Treat `#include` and package imports as load configuration: use a
loaded source/header root rather than quietly modifying the running program
from a live directive. User-defined x2c macro/meta/protocol surfaces can be
authored in loaded source; incremental definitions of those forms are not a
separate deliverable.

Top-level declarations create stable, typed, worker-owned storage. Native
factories establish its actual size, alignment, initialization, and cleanup;
do not calculate C layouts in a parallel interpreter. Capture existing object
addresses by binding identity, as compiled prompt functions already do.
Assignments update those objects without moving their storage. Keep static
array extents, const restrictions, references, and normal struct copying.

Compile executable input into a native entry that runs once. It captures only
the prior declarations it uses. Capture a final expression in a typed result
object before rendering it, so result inspection never reruns the expression.
Generated adapters know the actual type; arbitrary native records need not fit
into `Var` or a serialized value. Earlier code and objects are not rebuilt.
Render a temporary result while its native lifetime is still active; only the
formatted result leaves the entry. Do not return a pointer to a thunk's local
record as a retained inspection value.

Prompt-defined named functions expose genuine C ABI entry points, with
module-owned access to their bound session environment. Existing session
binding rewrites can supply those addresses; keep the context out of the
public function signature. A module has one binding environment in its worker.
Code may be cached across workers; mutable environments and literals must not
be shared across worker processes or temporary parsing contexts.
Include the symbolic binding/environment identity and native compile inputs
in module identity. Two bodies with the same generated shape can capture
different objects. Initialize an environment once before publication; never
rebind a live module environment on a cache hit. A repeated submission may
reuse code only with the same committed binding environment.

This permits ordinary calls, function pointers, struct arguments/results,
out-parameters, pointer arithmetic, and named C callbacks. Verify `qsort` and
a library callback with a `void *userdata` parameter. x2c `Func` closures retain
ordinary compiler adaptation rules; do not silently cast arbitrary captured
closures to context-free C function pointers.

The direct top-level prompt is one session scope. Persistent declarations,
compiler-produced managed-cleanup temporaries, and direct top-level `defer`
registrations live until orderly worker retirement. Run registered cleanups
once in reverse order before releasing their bound objects and native modules.
An explicit block or function call retains its normal automatic lifetime.
This deliberately replaces the REPL's submission-local top-level cleanup;
it does not change cleanup in ordinary source programs.

Preserve the book's distinct cleanup meanings. Declaration `auto T x = ...`
cleans the binding's current value at scope exit. Initializer
`T x = auto acquire()` or `$auto(acquire())` saves the acquired value and cleans
that value despite reassignment. Explicit `defer release(x)` reads `x` when
the cleanup runs. Use compiler-produced cleanup and worker-owned storage for
saved values, not name-based destructor inference. A failed multi-declaration
cleans newly acquired managed objects through the ordinary failure path before
discarding its provisional names; effects on earlier objects remain.

Do not extend dangling C pointers' lifetimes. Raw library allocations retain
the library's explicit release contract. Orderly quit, reset, and replacement
run session cleanup. A crash or forced stop cannot guarantee cleanup or undo
external effects. Supervise orderly retirement too; a hanging destructor must
not trap the terminal and may require forced retirement.

For this first design, assignment updates existing variables; duplicate prompt
definitions remain rejected. `:reset`, `:reload`, and explicit replay provide
the replacement loop. Live function/type replacement, raw callback retargeting,
and old/new definition version semantics are deferred together.

Syntax/type/link failures publish no new definitions. Failed initializers
publish none of their declaration's names. Existing-object mutations and
external effects already performed remain. An ordinary caught x2c Error can
return control to the same worker; a fatal native failure retires it.

## Object inspection

Use one typed renderer for final expression results and `:inspect`. Display
the declared type and useful structure, consistently for prompt objects,
loaded globals, local expression results, and returned records.

- Scalars and known x2c value types use their normal readable forms. Fixed
  arrays show extents and indexed values. Structs show named fields, including
  nested records. Native field readers use the original declarations.
- Pointers show type, nullness, and address. Never follow a raw pointer
  automatically. `:inspect *p`, `:inspect p[2]`, or an explicit library query
  requests the actual read. Opaque pointees remain opaque and expose their
  declared operations through discovery.
- A raw `char *` also remains a pointer. Use an explicit String conversion or
  a library length/query operation to inspect text. Character arrays may show
  bounded bytes. Do not guess that arbitrary pointers designate C strings.
- For unions, show the type and selectable members; do not guess the active
  member. An explicit member expression reads that member. Bitfields use
  native field expressions. Skip volatile fields during automatic traversal
  and label them; explicit expressions retain normal volatile semantics.
- Default to depth 3 and 100 displayed entries in total. Mark truncation and
  show how to inspect a selected field or raise the limit. Limits bound display
  work; they do not claim that a C pointer is valid.

Inspection does not call arbitrary user methods or getters to discover
contents. Expression evaluation happens once and can have ordinary effects;
`:info`, `:members`, and `:source` do not execute the submitted expression.
A bad explicit dereference can crash the worker. Report the native failure
and restart under the same recovery rule as a bad library call.

## Terminal, restart, and transcript

Only source requests, descriptions, diagnostics, status, and formatted output
cross between supervisor and worker. Native objects and callback addresses
never cross. Use dedicated control pipes so library stdout/stderr cannot be
mistaken for protocol messages. Reuse existing process and framing operations
where they fit; do not broaden the compiler's meta-helper object protocol.

The supervisor owns terminal modes and the session transcript. While editing,
Ctrl-C cancels pending input. While executing or compiling, Ctrl-C terminates
the active worker/job group and returns to the prompt with a fresh worker.
During candidate load/reload preparation, Ctrl-C instead cancels only the
candidate job group and leaves the previous session active. Publication is
the point at which that distinction changes.
An exit, crash, or forced stop clears all live state, reports the reason, and
starts from the last successful program artifact when its external native
dependencies still match. Do not install signal-based
recovery inside arbitrary C frames or claim heap rollback.

No default short runtime timeout applies to ordinary library calls. The user
can stop a long call explicitly. Interactive native stdin uses the terminal
while the supervisor is not reading a submission. Piped submission input is
kept separate; native stdin gets EOF rather than consuming subsequent source.

Persist command history under `$XDG_STATE_HOME/x2c/repl-history`, falling back
to `$HOME/.local/state/x2c/repl-history`. Keep in-memory recall bounded as today.
History is text, never a live-value store.
The replayable transcript records successful submissions, load/reset boundaries,
and launch configuration. Preserve diagnostics and failed text separately for
correction. Failed submissions can leave partial external or existing-object
effects that a successful-input script cannot reproduce.

`:save` captures instructions and build configuration, including original path
bases; it neither freezes dependency versions nor serializes native resources.
`:replay` is an explicit rerun against the recorded sources/configuration,
with normal side effects. Never replay automatically after a crash or load.

## Connected implementation

Implement the following coherent changes in dependency order. They can share
a delivery batch; the internal steps do not require individual publication.

1. **Own the session in a worker.** Separate terminal ownership in `repl.x`
   and `repl-input.x` from session execution. Preserve structured results,
   diagnostics, completion, history, and piped exit status. Add restart and
   retained-artifact ownership at this boundary.
2. **Load native programs and compile submissions.** Adapt `repl-session.x`,
   `repl-native.x`, and `repl-load.x` around ordinary native storage and entry
   points. Reuse `Frontend`, `meta-project`, staged emission, the ordinary
   toolchain, and caches where their contracts fit. Keep ordinary compiler
   meta execution unchanged. Delete REPL transport-specific global selectors,
   crossing adapters, reconstructive header layouts, manual Lisp lowering,
   and REPL-only Lisp runtime operations once the native path replaces them.
   Do not leave an alternate execution mode or expand the shared Lisp engine.
3. **Export source descriptions and expose exploration.** Retain source
   snapshots with committed declarations. Implement symbol/info/source/member
   queries and typed object rendering. Drive help and completion from the
   same command descriptions and binding queries.
4. **Finish the repeatable workflow.** Add explicit reset/reload/save/replay,
   persistent history, build configuration inputs, and end-user documentation.
   Update the existing REPL README and book guide, including changed lifetime,
   raw C string display, interruption, and restart behavior.
5. **Review and fix the completed authored diff before publication validation.**
   Remove superseded tests of mechanisms, preserve tests of retained behavior,
   review generated changes, and deliver only when implementation is requested.

## Evidence and acceptance

The planning survey rebuilt stage 0 and the REPL, then passed
`sh commands/repl/tests/run.sh`. Additional temporary fixtures established:

| Baseline observation | Required playground outcome |
| --- | --- |
| `:symbols` lists loaded names, but `:info` omits parameter names and rejects types/values. | Readable discovery and consistent declaration/type/member queries. |
| `:source` is absent; loaded `:ast` reports "not a session function". | Exact captured source or an explicit declaration-only result. |
| Loaded record globals print fields; prompt records print an address. | One typed aggregate display policy. |
| A record returned by a library cannot cross the helper boundary. | Declare, return, copy, inspect, and pass that record natively. |
| Header-defined records fail prompt construction while an inline equivalent works. | Both use the original native declarations and work identically. |
| Loaded globals can be passed by address, but prompt-owned records cannot. | Both refer to actual same-process native objects. |
| Returning a native pointer fails; one record-pointer path gives a misleading staging error. | Keep a returned pointer and use it on later submissions. |
| Loading another file resets loaded globals but preserves prompt definitions. | Announced full-session replacement, with no dangling survivors. |
| A compiled prompt assertion terminates the REPL. | Worker terminates, supervisor/history survive, fresh prompt is available. |

Survey transcripts are in this workspace's ignored
`debug/repl-survey-transcripts.json`; the existing-check log is
`debug/repl-survey-tests.log`. They are local evidence, not durable dependencies.
Recreate minimal fixtures in the existing REPL tests during implementation.

The end-to-end checks must cover a source/header C fixture with pointer-owned
objects, aliases, nested fields, arrays, an attributed/packed record, a struct
return, out-parameters, enums and macros, and ordinary callbacks. Link the same
fixture as an external archive to prove header-plus-library use. Exercise an
opaque handle and a borrowed pointer whose documented owner stays alive.

Use the existing platform SQLite C API, when available, as a real-library
walkthrough: open an in-memory database with an out-parameter, prepare a query,
step, read a column, finalize, and close. Report host availability explicitly;
do not install it. The deterministic fixture remains the portable check.

Check source lookup after a disk edit but before reload, method spelling,
delegated completion, one-time expression evaluation, const/volatile behavior,
display truncation, session versus block cleanup, managed reassignment and
failed-initializer cleanup, distinct cached binding environments, reset with
edited headers, changed native dependencies, failed publication, candidate
cancellation preserving the old session, successful replacement clearing it,
native crash/exit/hang recovery, stdout/stderr/stdin, and explicit replay.
Preserve existing x2c collection,
lambda, Error, and ordinary compiler behavior in the native path; remove only
expectations that enforce the superseded execution boundary.

Extend the current REPL checks rather than add a validation target or recurring
gate. Implementation delivery follows the root publication rules, including
the applicable existing gate and performance checkpoint. Planning alone needs
no compiler publication gate.

### Performance boundary

On this Mac, six small native prompt function definitions at the baseline took
70.05-86.00 ms each, measured from writing a submission to its result. Six
interpreted calls to an already compiled function took 0.97-1.49 ms each.
The first variable submission, including process initialization, took
159.74 ms. These are small-function observations, not an end-to-end measurement
of the proposed backend. Local evidence: `debug/repl-playground-timing.json`.

The selected design accepts compilation work for each new executable
submission. Reuse compiled artifacts for repeated identical code and never
reexecute old initializers to obtain a cache hit. Before implementation
delivery, measure startup, source/header loading, new submissions, repeated
submissions, and long sessions separately. Record absolute times and retained
code/storage; do not describe faster native execution as proof of faster
interaction. No JIT, second evaluator, or new performance gate is selected.

## Compatibility and scope limits

The runtime ABI, language ownership rules, ordinary macro binding, compiler
meta-helper semantics, and native library contracts remain premises. Existing
REPL commands stay recognizable, but Lisp dump output and partial state
survival after load are deliberately superseded. Document that public change.
Separate worker processes replace same-process multi-session assumptions in
the internal REPL API; cached code must still keep sessions isolated.

This plan does not promise arbitrary compiler extensions beyond the ordinary
configured x2c/host-C toolchain, ownership inference for C pointers, automatic
union selection, safe reads from invalid addresses, opaque-struct decompilation,
live state migration, function hot replacement, or asynchronous GUI/event-loop
integration. These limits do not exclude ordinary C callbacks or stdin use.
Modules may remain resident until worker retirement. Reset gives a real
reclamation boundary; no garbage collector or live module unloading is added.

## Design review

The ordinary compiler establishes binding, type, initialization, cleanup,
calling convention, and emitted C. The host C compiler establishes layout
against the original headers. Native storage and module lifetime preserve
identity inside one worker. Source producers establish immutable descriptions;
the terminal consumes those descriptions and formatted results.

The worker boundary earns its cost by containing crashes and providing a
deterministic stop/reset operation. Full-session replacement avoids a second
ownership system for old pointers. Native compilation replaces manual
execution machinery rather than adding another backend. Retained module
contexts address the archived in-process lifetime failure; closing temporary
source contexts beneath live native literals remains invalid.

Delete REPL-specific transport/layout/interpreter paths as their consumers move
to native execution. Keep compiler-owned helper operations used by ordinary
translation. Add no global allocator lock, generic FFI engine, remote-object
registry, speculative pointer-validity checker, or new recurring process.
Tests establish observable library behavior and publication boundaries, not
the preservation of superseded implementation details.

The architecture and restart policy are selected. Native staging and compiler
services establish the available building blocks; the complete replacement
backend, its latency, and its platform behavior remain to be implemented and
verified. No prototype failure from an earlier lifetime arrangement rejects
the selected architecture as a family.
