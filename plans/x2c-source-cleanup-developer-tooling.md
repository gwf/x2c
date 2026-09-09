> Status: active
> Gary approved this plan with the review amendments on September 9, 2026.
> Implementation starts from main at 4d5b2dd. SQLite is accepted and delivered;
> the previous program is complete and archived. Native prefix installation
> and movable binary bundles are newly approved distribution scope.

# Finish source cleanup and developer tooling

## Result

Carry out the approved follow-up work from the repository review: remove real
source duplication, produce clean and dependable generated files, make the
compiler and existing semantic editor features usable outside a checkout,
deliver movable native package bundles, and settle the remaining performance
candidates with current evidence. Preserve the shipped language and runtime
APIs. Do not turn the original discovery list into a deletion quota or a
promise to implement every suggested new language or library feature.

This follows [the delivered program](archive/x2c-correctness-performance-tooling.md),
[the declaration design](x2c-declaration-discovery-design.md), and
[the source-package proof](x2c-source-package-proof.md). Their completed work
is the starting point, not work to repeat.

## Established starting point

The landing review rebuilt 3aa865f in an isolated checkout. It passed 748 unit
tests / 18,320 assertions and 597 compiler fixtures / 1,387 artifacts. All 92
runtime C/H files agreed across serial, parallel, and reversed translation.
String/literal equality, lambda arguments, library replacement, the three
gallery examples, source mapping, and the native editor queries worked.
These results establish the starting behavior, not publication evidence for
future edits. Historical performance percentages are not current promises.

Follow-up inspection establishes these remaining details:

- `transform.x` repeats `_finish` at the end of `_node`; `cache.x` still
  constructs five spacing placeholders; comma tokens and the formatter both
  supply spaces. `generate.x` still opens final C/H destinations with `w`.
- The Exceptions example succeeds but warns about a missing return.
  `Emitter._filtered_catch` emits independent `if` statements even though
  `lib/error.x:_catch_match` selects exactly one matching arm before unwind.
  A temporary generated-C probe using an exclusive chain with a final `else`
  passes `-Werror=return-type` and the example's assertions.
- The documented NULL macro reproducer now succeeds. Its outstanding-item
  entry is stale; the workaround in `src/ast-rewrite.xmacro` needs the exact
  internal-use check described below before removal.
- `translate -j8` and `translate -Ilib` still suggest nonexistent `--j8` and
  `--Ilib`; the shared option parser already accepts attached forms for build.
- `gate-state.py record` can label a tree as passed without executing a gate.
  A probe with temporary state and an inert digest reproduced this behavior.
- Native prefix installation is missing. Source bundles work, but native
  package link files contain checkout/cache paths and carry no C include
  options. Copying their archives is not a relocation solution.
- Editor queries work, but the standalone worker duplicates compiler linking
  and must be built and selected separately. On macOS, mapped debug binaries
  need retained objects or a companion dSYM. A dSYM probe stopped at the
  original `.x` line with reads of the original object directory denied.

## 1. Correctness and command-line polish

### Catch emission and generated-file writes

Change `_filtered_catch` to emit one exclusive chain: `if`, zero or more
`else if` arms, then unconditional `else`; one arm needs only its body and
scope. Reuse the already selected arm, detach operation, binder construction,
and cleanup emission. Do not add a flow analyzer, dummy return, unreachable
assertion, or second test of whether the runtime selected a valid arm.

Write generated C/H to unique sibling temporaries and close both before
publishing either with individual renames. Reuse the depfile writer's pattern
and the current compiler I/O diagnostic owner. Keep stdout streaming. Failed
write/close/rename leaves that destination's previous contents intact and
cleans up the temporary where possible. This promises complete individual
files, not an atomic transaction across a C/H/depfile set; a failed invocation
still fails and its build must not proceed. No fsync policy, rollback manager,
or preflight validator is needed.

Verify the Exceptions example under `-Werror=return-type`, single/multiple
catch arms, rethrow and cleanup, and the existing Error fixtures. Exercise
handled output failures with an existing sentinel destination and inspect
successful ordinary and source-mapped C/H. Keep fault injection confined to
focused probes; do not add a permanent failure-injection subsystem.

### Small CLI and evidence fixes

- Remove the translate-only exclusion from attached short-option matching.
  Preserve separate values and existing long forms. Offer a one-dash migration
  hint only for an actual known old spelling; use the existing unknown-option
  diagnostic otherwise.
- Suppress the redundant limit notice when the configured diagnostic limit
  is one. Preserve the first error, stopping behavior, counts, and notices
  for larger limits. Do not expand parser recovery.
- Make the run receipt say intermediates are removed after the run, which is
  when cleanup occurs. Keep current output defaults; document `-q` and
  `--build-dir` for quiet and retained runs. Add no hidden global build cache.
- Remove the public `gate-state.py record` command. Keep success recording
  private to `ensure`, after its gate succeeds. Invalidate the old record
  format once so an old manual stamp cannot be reused as executed evidence.
  Keep `check`, configuration fingerprints, and existing gates. This removes
  a misleading shortcut; it adds no gate or authentication mechanism.

Use the existing CLI, diagnostic, and gate-state tests. Check attached versus
separate arguments, exact error output, successful reuse, and that a failed
gate cannot create a successful record. Do not make these tools or their
optional test runners new prerequisites of precommit.

## 2. Connected source cleanup

Replace `_node`'s duplicate dispatcher tail with `_finish`, preserving the
special origin, raise, block, and operator-chain handling before that tail.
Use canonical Match patterns and literal templates for the connected rewrite;
preserve List identity and the existing fixed-point semantics.

Replace conformance/member destructuring followed by `(void)` discards with
patterns that name only the fields used. Keep both protocol walks:
`install_generated_protocol_symbols` discovers signatures, while
`generate_protocol_adapters` emits definitions using completed function and
source-typedef facts. Their different eligibility and ordering are meaningful.
Do not merge them or cache a second conformance representation merely because
they inspect the same rows.

Remove empty cache-spacing placeholders, reusing conditional declaration
insertion already present in `cache.x`. Make `_need_space` recognize an
existing boundary space/tab instead of adding another separator. Preserve
token contents and existing vertical spacing. Check ordinary, macro, and mapped
output; regenerate and review exact C fixtures and bootstrap through their
owning commands. Do not remove semantically necessary comments or declarations
to minimize generated output.

Remove the stale outstanding-item text after replaying its example. Before
removing the internal NULL workaround, use a disposable compiler build with
that exact macro changed to NULL and self-translate its actual consumers.
Remove the cast/comment only when that use passes. Apply the style guide to
the touched authored functions, including
comments broken into unnatural fragments. Do not start a repository-wide
comment rewrite.

The scanner consolidation candidate is closed with no forced rewrite. The C
scanner, strict x2c scanner, and permissive String decoder differ in escape
widths, malformed/incomplete status, CRLF, dollar handling, and unknown
escapes. Those differences do not warrant a configurable scanner framework.

Validation uses the existing transform, protocol, scanner, macro, formatter,
source-map, and generated-output coverage. The expected differences are the
reviewed formatting and catch-emission changes, not altered language meaning.

## 3. Finish the performance investigation

Run one bounded campaign against the then-current compiler. Use the existing
iterator, List, Scope, Error, Match, and shootout benchmarks; add temporary
probes only where the existing workload cannot distinguish causes. Record
optimization mode, toolchain, fixed inputs, elapsed time, aggregate CPU, and
allocation/retention evidence when it explains the result. Measure alternatives
in an otherwise quiet window with alternating before/after runs.

Profile once, select at most three candidates with material measured costs,
and work in this priority order:

1. Compare Array/List `foreach`, explicit `Iter`, and direct traversal, then
   native callbacks versus equivalent `Func` calls. Prefer removing repeated
   work inside current adapters and call operations. Any compiler fast path
   must use resolved collection/conformance facts, evaluate the source once,
   and preserve exhaustion, mutation visibility, element conversion, custom
   iterators, `break`/`continue`, and exception cleanup. Preserve public
   layouts and callback ABIs; do not add `call1`/`call2` API families by
   default.
2. Profile remaining Var classification/dispatch and repeated compiler walks.
   Reuse already established facts only within their valid scope and lifetime.
   In particular, do not delete a fixed-point pass or generation-phase
   transform merely because an earlier transform ran: later work adds syntax.
   Try direct structural dispatch where the current profile justifies it;
   prior rejected Match experiments are evidence, not a permanent prohibition.
3. Examine Block growth, Scope statistics, and Error construction only when
   they remain visible costs in current workloads. Preserve shared counters,
   allocation lifetimes, canonicalization, and Error transfer semantics.

Each candidate ends with either a smaller/faster implementation and measured
evidence, or a concise recorded rejection with its reason. Repeat or broaden
measurements only for a changed candidate or an unresolved result. An unchanged
implementation is a valid conclusion when the prototype adds machinery or
does not improve the target workload. Report whole-compiler results separately
from microbenchmarks; promise no target percentage.

Keep stage translation parallelism opt-in. The earlier evaluation is complete;
this plan neither adds a stage matrix nor makes benchmarks mandatory gates.

## 4. Actual native installation and movable packages

### Install the compiler

Extend existing `make install` with explicit `PREFIX` and `DESTDIR` support.
Without `PREFIX`, retain the current branch-named checkout-bin behavior.
With it, install a complete dedicated x2c prefix: `bin/x2c`, the matching
runtime archive, materialized include files, compiler/runtime source support,
symbol artifacts, compile-time Lisp SDK, and licenses. Reuse one support-copy
recipe with the existing APE payload builder; native installation must not
require an APE build. Do not copy checkout-relative include symlinks or record
the staging directory as a runtime path.

Stage the complete payload before publishing it. Support a fresh prefix and
replacement of x2c-owned files in a previously installed dedicated prefix.
Reuse the APE payload's generated file inventory to remove only obsolete files
listed by the previous installation; leave unrelated contents alone and do
not recursively remove the prefix. Install `lib/x2c/toolchain` with portable
`CC=cc` / `AR=ar` defaults, retaining normal explicit/environment
override precedence. Record build identity separately from tool selection;
do not pin a temporary build tool path in a distributable prefix.
Document that system-wide merged layouts and cross-platform binary execution
are outside this dedicated-prefix contract. Use the existing executable-based
root and toolchain resolution, correcting any path assumption exposed by the
relocation probe rather than adding an installation registry.

Completion requires the real install command, not a hand-copied fixture.
Install into a temporary prefix, relocate it, make both the producer checkout
and old prefix inaccessible, and run direct and manifest builds, optional
runtime includes, compile-time Lisp/macros, and source-package consumers.
Include spaces in installed paths and quote the compiler argument in shared
package Make recipes. Test `DESTDIR` staging separately. Document one short
install/build/debug/package workflow in the book.

### Bundle built packages, including their native inputs

Add an optional package-local bundle target through `packages/package.mk`.
Its result is a directory/tar archive accepted by existing `--package-dir`:
package source interfaces, generated public headers, `lib<name>.a`, licenses,
and explicitly selected native headers/static archives under `native/`.
Keep source distribution and legacy `.link` consumption working unchanged.

Use optional distribution data in the existing dependency manifest for source
files to copy and ordered native arguments. Do not infer dependencies by
crawling linker output. The first supported bundles are pure/mixed packages,
yyjson, and libcurl's declared transitive static inputs; use the same mechanism
for the other already integrated packages when their admitted build supports
it. SQLite remains outside this assignment, and package acceptance status does
not change because a bundle works.

For new bundles, emit `builds/<name>.native.rsp`. It carries native include
options and final-link inputs, which legacy `.link` cannot express. Reuse the
existing response-file quoting/tokenization and native option application;
separate tokenization from `@` expansion rather than writing a second parser.
Expand the literal `{package}` in already tokenized arguments to the resolved
package directory, so spaces remain inside a single argv element. Do not use
shell evaluation. Existing dependency templates already use this spelling.

The package reader accepts native compile/link options and archive inputs,
not options that replace the consumer's output, command, or tool selection.
Apply include/define options while compiling both libraries and executables;
add archives/system link flags only at final executable linking. Preserve
argument order and existing package deduplication: keep native archives in the
sidecar's ordered link stream after the wrapper archive, rather than moving
them to the ordinary input bucket. Definitions affect native C compilation,
not prior x2c source preprocessing. The allowed options are C include/system
include, `-D`/`-U`, `-L`/`-l`, archive inputs, `-pthread` routed to native
compilation and linking, and an ordinary
`-framework <name>` native option added to shared CLI handling for macOS.
Do not admit unrestricted `-Xcc`, `-Xlinker`, or `-Wl` escapes through package
metadata. When the sidecar is
absent, preserve the old `.link` path exactly. New bundles require the compiler
that implements this format; do not pretend old compilers understand it.

These are static, host/architecture-specific bundles for the matching x2c
runtime/compiler, with native system libraries supplied by the host. Include
build/toolchain identification in the bundle documentation. Do not promise a
stable cross-version ABI, shared-library relocation, universal dependency
resolution, a registry, or automatic downloads during consumer builds.

Unpack and move each pilot bundle, deny access to checkout and dependency
cache, then compile and run a fresh external consumer with the installed
compiler. Cover C-header use, ordered transitive native libraries, static
library consumers, paths with spaces, repeated imports, and old `.link`
packages. Spaces in installed compiler, extracted bundle, header/archive, and
consumer paths are required. Arbitrary source-producer and dependency-cache
paths containing spaces are not established by sidecar support: keep producer
builds on the currently supported Make paths and document that limitation.
Preserve the existing dependency checksum and license checks; do
not add a second package-validation system or mandatory packages gate.

## 5. Make existing editor and debugger features easy to use

Move the current one-request adapter from `tools/x2c-editor/worker.x` into
`src/editor.x`, reached through private `x2c editor` dispatch. Keep its argv
metadata, snapshot files, separate JSON response file, and ordinary compiler
configuration after `--`. Reuse `Frontend`, `ParsedUnit`, `SourceView`, binding
facts, query rendering, and process-per-request lifetime unchanged.

Selection order is explicit `x2c.semantic.compilerPath`, explicit legacy
`x2c.semantic.workerPath`, trusted workspace `./x2c`, then `x2c` on PATH.
It must not build workspace code automatically. An explicitly configured
missing or incompatible compiler produces an actionable error instead of
silently selecting another compiler. Use `configuration.inspect`
to distinguish an explicit legacy override from the old default. The compiler
path prepends `editor`; legacy paths retain their existing argv transport.
Retain only a thin compatibility launcher/target for standalone-worker
users, deleting its separate compiler archive and duplicate adapter build.

Keep cancellation, dirty overlays, UTF-16 conversion, macro stdout isolation,
project/target configuration, and trust checks. Missing tools should produce
one actionable setup message, not repeated per-keystroke failures. Document
and package the VSIX with the new defaults, and exercise the actual extension
in a fresh VS Code profile in addition to existing native and JS tests.
Marketplace publication is a separate external release action, not implied
by writing this plan.

For macOS executable builds with effective debug information and source
mapping enabled, including manifest configuration equivalent to `-g` and
`--source-map`, run the native `dsymutil` action before temporary objects are
removed. Determine effective debug information from the final ordered native
compiler arguments, including `-Xcc -g0` overriding an earlier manifest `-g`. Produce the
matching companion `.dSYM`; failure fails the debug build and retains the
intermediates for diagnosis. Keep explicit retention options and Linux debug
behavior. Do not promise atomic replacement of a binary/dSYM pair. Verify
breakpoints and backtraces after moving the executable and dSYM and denying
access to the old object directory, including optimized code and cleanup.

This intentionally adds symbol-assembly time to requested macOS mapped debug
links. Approval to implement this plan must include that explicit build-time
tradeoff. It adds no work to ordinary builds or precommit. Record the measured
debug-link cost before delivery; preserve source mapping as an opt-in because
it changes native `__FILE__` and `__LINE__` behavior.

Completion, rename, workspace indexing, native-CPP unsaved-buffer support,
incremental semantic caches, and a general LSP are separate feature expansions.
This assignment completes delivery of the existing three semantic providers.

## 6. Close repository and documentation loose ends

Remove `site/src/deprecated` only after confirming it is absent from the live
site imports/routes and moving any still-used asset or content into its current
owner. Use the site build to verify the result. Do not delete public runtime
APIs, Make aliases, generated API documentation, the recursive Match oracle,
or optional Python tests just because repository callers are scarce.

Repair touched setup/help links and stale failure claims. Keep source-debug,
editor, compiler installation, and package instructions in the book; tools and
agent guidance should link there. The parent and SQLite plans are already archived with their delivery outcome;
keep those references current. Update
this plan as work lands rather than leaving completed assignments marked open.

Give file-static native macro/tag placement its own bounded design assignment.
Its required behavior is already settled: preserve native expansion order and
inline-tag scope while retaining deferred runtime evaluation. Prototype both
the `__COUNTER__` and inline-tag cases from `unittest/STATUS.md`, together with
macros in type bounds. A source-position thunk alone moves tags into the wrong
scope; naive tag extraction can reorder macro expansion. Reuse the existing
initializer conversion/native-type operations and select an implementation
only after one prototype preserves both properties. This design result must
state the actual fix or why implementation remains open; documentation alone
does not close these known compatibility defects.

Local-static runtime-valued aggregate initialization is different: its
first-use/startup, retry, recursion, and threading semantics need Gary's
decision before implementation. Keep it accurately documented and tracked as
a separate language proposal. An invented boolean guard is not a cleanup.
Neither group was introduced by the recent chained-initializer work.

Likewise, new filesystem/process/time libraries, extra collection APIs,
compile-time Lisp language changes, public API removals, and broad declaration
discovery are not unfinished implementations from the delivered program.
Their disposition here is explicit deferral, not an assertion that they landed.

## Delivery order and completion

1. Deliver correctness/CLI polish and connected source cleanup as a coherent
   batch. Use the existing focused probes while editing.
2. Native compiler installation and compiler-integrated editor work can
   proceed independently. Coordinate their shared `main`, CLI, toolchain,
   support layout, and generated artifacts before validation. Then complete
   movable package bundles and macOS debug artifacts on that shared result.
3. Run the bounded performance campaign against an integrated, stable build;
   source discovery and the native-initializer design assignment can run in
   parallel, but competing builds must not distort measurements. Deliver only
   the justified changes and record rejections.
4. Finish the documentation/site closure and check every assignment above has
   its promised result or its explicit scoped disposition.
5. As the last implementation step of each delivered batch, review and fix the
   completed authored diff for duplicate facts, unnecessary checks, missed
   deletion/reuse opportunities, and idiomatic x2c. Then integrate current
   main and use the root publication command for the resulting tree, reviewing
   its generated changes. If integration changes authored code, repeat that
   source review before ensuring validation. Publish through the root's
   explicit main destination only when implementation is authorized.

One coordinator owns integration, artifacts, and publication; use up to three
workers for independent source, runtime, and tooling work. SQLite is already delivered and accepted; its bundle remains outside this
assignment.
No new recurring gate, benchmark matrix, review document, or package test
requirement is introduced. Optional focused checks remain optional outside
their relevant implementation work.

## Plan review

- **Established facts:** catch selection is committed by Error before unwind;
  bindings/types/conformances belong to the ordinary compiler; canonical List
  identity belongs to `cons`; allocation and shared Error calls do not return
  failure. Proposed consumers use these facts without origin checks, repeated
  shape validators, null-after-allocation checks, or speculative rebinding.
- **Deletion and reuse:** reuse `_finish`, phase-specific protocol operations,
  formatter spacing, depfile-style writes, CLI option/response parsing,
  dependency manifests, APE support copying, native build actions, and the
  existing editor adapter. Delete duplicate tails, placeholder spacing,
  stale NULL workarounds, public manual gate stamping, and duplicate worker
  linking. Keep scanner differences and declaration phases that carry meaning.
- **New mechanisms:** sibling temporary files protect existing outputs; a
  native install target and the reused payload file inventory supply the
  missing distribution operation and preserve unrelated prefix files; bundle
  copy data and native response arguments carry required files, C options,
  and relocatable paths missing from `.link`; private editor dispatch replaces
  a separately linked executable; dSYM assembly makes requested debug output
  independent of temporary objects. No generic package manager, compiler
  framework, persistent semantic cache, or new runtime representation is
  proposed. Performance prototypes must earn any lasting mechanism.
- **Checks and diagnostics:** keep native I/O failure reporting to prevent
  truncated successful artifacts; restrict bundle metadata to its deliberate
  native-argument role so it cannot redirect the consumer's build; retain
  existing dependency checksum checks and editor trust/configuration behavior;
  report missing/failed requested debug-symbol assembly as a build failure.
  Focused negative cases cover those observable failures and failed-gate
  recording, not earlier rejection of arbitrary source. No new AST validator
  or dedicated language diagnostic is proposed.

## Execution status

- Batch 1, correctness/CLI and connected cleanup: published in `d158e7f`.
  The full publication gate, existing seven-package check, SQLite checks, and
  site build passed; the Pages deployment succeeded.
- Native compiler installation: implemented and relocation/DESTDIR verified;
  delivered with batch 1.
- Compiler-integrated editor, movable bundles, and macOS dSYM: implemented;
  focused verification is in progress before the second publication.
- Bounded performance investigation: prepared; waits for the stable second
  batch and a quiet measurement window.
- Native-initializer design: bounded prototype complete, candidate rejected.
  Macro prescanning plus an unevaluated type anchor preserves counter order
  but repeats inline tags inside the deferred function, changing type identity.
  A forward-declared typed callee exposes the mismatch. The native placement
  defects remain open; no source fix or warning suppression was accepted.
- Final documentation/site closure and publication audit: queued.

Approval includes the opt-in macOS mapped-debug symbol-assembly cost stated
above. Existing source-package delivery is complete; native installation and
binary bundles extend that accepted milestone. No new recurring gate is added.

### First delivery evidence

The Exceptions application compiles with `-Werror=return-type` and runs.
Focused generated-output probes preserve sentinel files on handled failures,
clean temporary siblings, and accept long legal filenames. CLI boundary checks
pass, including attached options and the run receipt; focused Error, Exception,
and diagnostic tests pass (53 tests, 250 assertions). The internal NULL macro
passes isolated stage-0/stage-1 self-translation and the exact reported caller.
The fixture owner regenerated 1,387 artifacts across 597 fixtures: changed C/H
is spacing and catch dispatch; diagnostic changes remove only limit-one notices.

Real native installation passes fresh installation, upgrade, DESTDIR, moved
prefixes with spaces, and external direct/project/source-package builds with
producer access denied. Shared APE inventory hashes agree with the previous
implementation. Evidence logs are `debug/followup-cli.log`,
`debug/generated-output-final.log`, `debug/cleanup-null-selfbuild.log`,
`debug/native-install-proof.json`, and `debug/native-install-ape-inventory.log`.

### Second delivery evidence

The integrated editor passes both native transports (18 tests), 12 JavaScript
tests, both grammar fixtures, and six workflows in an actual installed VSIX
0.3.0 in a fresh VS Code 1.136.1 profile. Missing explicit compilers never
fall back; the setup message appears once.

All seven native package bundles build and run after extraction with spaces
in compiler, bundle, and consumer paths and producer/cache access denied.
Pure/mixed bundles, native C headers in a static-library consumer, repeated
imports, ordered dependencies, legacy sidecars, restricted metadata, frameworks,
and empty run arguments also pass. Raylib retains its documented explicit
source include option; SQLite bundling and untested platform profiles remain
outside the verified result.

Mapped debug builds at O0 and O2 produce movable dSYM companions. LLDB reaches
original source breakpoints and backtraces and executes cleanup with old object
access denied. Manifest debug settings, later -g0, ordinary unmapped/no-debug
builds, and failed symbol-assembly retention pass. Standalone symbol assembly
took about 17 ms for this small program; this is not a general debug-link cost.

Focused logs: `debug/editor-vscode-proof.json`,
`debug/editor-native-transports.log`, `debug/native-bundle-proof.json`,
`debug/bundle-mixed-proof.json`, `debug/native-options-proof.json`, and
`debug/dsym-proof.json`. The existing CLI suite passes all 110 probes.

The unused `site/src/deprecated` tree had no active route, import, or asset
reference and was removed. The current installation chapter now uses movable
debug symbols rather than requiring retained object files.
