> Status: active
> Completion audit reopened September 9, 2026. The three implementation
> batches and site changes are delivered and validated, but the full plan
> now has the stage-translation evaluation, declaration-discovery design,
> stronger source-package proof, optional suite selection, sorting, and bounded
> HTTP work ready for integrated validation. Initializer completion is in
> progress. SQLite's concrete new-package scope awaits Gary's answer.

# Correctness, performance, and developer tooling

## Result and scope

Make ordinary examples and retained builds dependable, remove measured
compiler/runtime costs, and then improve source debugging, package production,
and semantic editor support. Deliver useful changes along the way rather than
holding correctness repairs for the entire program.

The coordinator owns integration and delivery. Use at most three worker
subagents alongside the coordinator. This is one project plan, not a new
recurring workflow or a requirement to write a plan for every small change.
Implementation and publication follow the root AGENTS.md and the matching
existing task skill. Planning alone does not publish product changes.

## Verified starting point

- The collections guide's `String == "literal"` example compiles and prints
  `0` where the book promises `1`.
- `love/files`, `power/counting`, and `power/exceptions` abort from the
  repository root; each succeeds in its prepared fixture directory.
- Replacing a library selected with `-l` leaves a retained executable marked
  current. The reproduced executable prints `1`; a fresh link prints `2`.
- Validation digests do not change with effective `CC`, `BUILD_MODE`, and
  `BUILD_LTO` overrides. Tracked configuration-file changes are already covered.
- Serial and four-worker translations of the same runtime inputs differ in
  seven C files, through extra declarations. This proves output inconsistency,
  not runtime miscompilation. The affected modules are iter, lib, lisp, list,
  map, tokenizer, and typed-map.
- List, String, and ordinary Symbol boxing already bypass `Var.new` after
  7557534. Do not repeat that work or use earlier profiles as current evidence.
- Repeated 200/400/800-term expression probes take about 0.05/0.14/0.49 seconds
  locally. These small probes establish scaling trouble, not a promised
  whole-compiler speedup.
- Wildcard catch already binds code and detail. Array indexed compound updates
  work; wrong-tag pointer-shaped reads return NULL. The values guide and old
  wildcard plan need correction.
- Session history recovered both original lambda failures: an expression
  lambda consumes a following argument, and parentheses prevent native
  callback adaptation. Both reproduce in the current compiler and are repaired
  through the existing expression parser, lambda lowering, and adapter.

Current source, tests, and the book supersede the pasted proposal's old
workspace links, counts, and performance predictions.

## Dispatch and integration

First dispatch three independent assignments:

| Worker | Assignment | Initial ownership |
| --- | --- | --- |
| Build correctness | B1: dependable final linking | `src/build.x` and relevant existing driver probes |
| Validation evidence | B2: effective configuration fingerprint | `tools/gate-state.py`, `tools/test_gate_state.py` |
| Examples and documentation | C1, then C2 | Named gallery slides, their generated examples, manifest rows, values/exception guides |

As slots become free, dispatch B3 and P1. After their evidence and any required
semantic decision, runtime work P2 can run alongside expression work C3/P3 and
one independent build/tooling assignment. Priority is correctness before
performance; dependency readiness, file ownership, and useful independent
work determine the exact assignment, not a fixed number of waves.

The coordinator uses these constraints:

- One worker owns each authored file at a time. In particular, serialize C3/P3
  and initializer work in `src/expressions.x`; B3/D1/T1 in generation; and
  B1/B4/T2/T3 in the native driver. B3 must settle shared compiler state before
  T5 extracts it. T1 and T5 cannot edit shared main/compiler adapters together.
- Workers report the observed result, authored files, focused proof, remaining
  uncertainty, and generated work needed. The coordinator verifies findings
  before integration and reassigns idle workers to independent ready work.
- In the shared checkout, the coordinator owns builds that replace `builds/0`,
  symbol/bootstrap regeneration, shared Makefile or harness edits, and Git
  publication. Workers use separate `/tmp` probe directories and an agreed
  stable compiler. Finish related edits before a shared build consumes them.
- Performance measurements run in quiet windows against fixed compiler and
  runtime snapshots. Do not benchmark while other agents build or profile.
  Source review and planning may continue during those windows.
- Finish and review coherent batches before publication. Every batch ends by
  reviewing and fixing the authored diff, integrating current `origin/main`,
  reviewing integration and generated deltas, and running the existing
  applicable publication command. Ensure it again only if its tree changes.
  Code uses `tools/gate-state.py ensure agent-pr-check`; documentation-only
  delivery uses `tools/gate-state.py ensure doc-check`. A failed check stops
  that publication, with full output retained under `debug/`.
- Routine implementation delivers to main under the root policy unless Gary
  requests otherwise. Only the coordinator pushes, with the explicit
  destination `git push origin HEAD:refs/heads/main`; never force-push main.

No new recurring gate, stage matrix, benchmark requirement, or publication
step is proposed. Acceptance below means focused evidence for the change;
reuse existing suites and probes rather than adding every case to a new gate.

## Correctness assignments

### B1. Dependable final linking

Preserve translation, object, and static-archive reuse; always execute the
native link for an executable. Limit final-state reuse and recording to the
actions whose inputs are actually known. Keep receipts truthful. Reuse
`Toolchain.link_action` and the real linker's search and selection rules.

This deliberately spends one link on unchanged executable builds. It avoids
implementing an incomplete second linker for `-L`, `-l`, package flags,
`-Wl`, `-Xlinker`, sysroots, and implicit runtime dependencies. The change is
a correctness repair, not an extra build or precommit process step.

Prove archive replacement changes executable output, earlier search-path
candidates affect selection, and an isolated runtime replacement causes a
link. Prove object compilation and unchanged static archives remain reusable.
Restoring executable-link reuse is optional later work, only after trustworthy
native dependency evidence covers both selected contents and changed selection.

### B2. Effective validation configuration

Keep the current file-state fingerprint and `ensure` flow. Derive effective
configuration through Make's own semantics; do not independently reproduce
its precedence. Include selected tool identities and effective build flags,
mode, LTO, and inherited overrides that affect the gate. Replace the literal
`cc --version` identity, and version the changed record format.

Inspect existing Make expansion before choosing a minimal read-only exposure
of configuration. Do not hash the entire environment. Unsupported wrapper or
tool inspection must decline evidence reuse rather than claim equivalence.
No new validation target dependency is needed.

Prove relevant overrides and changed compiler contents invalidate evidence;
restored identical configuration and unchanged staging/commit operations do
not. Preserve failed-gate behavior: failure never records successful evidence.

### B3. Translation order independence

Diagnose the minimal case separating header-cache replay from per-unit state.
Start in `src/collect.x`, `src/generate.x`, and `src/main.x`; involve
`src/type.x` only if the producer evidence points there. Restore declaration
facts at their existing owner. Do not delete necessary declarations merely to
equalize output, disable caching wholesale, or add an origin authenticator.

Prove C/H agreement for sorted serial and parallel runtime translation,
reversed order, and isolated affected units. Native compilation must retain
complete declarations. Existing self-host comparison supplies publication
coverage. This assignment precedes declaration cleanup and frontend extraction.

### C1. Executable example inputs

Edit the authoritative gallery slides `love-07-files.md`,
`power-01-counting.md`, and `power-06-exceptions.md` under
`site/src/content/slides/`. Add optional input arguments with repository-root
fixture defaults. The manifest supplies filenames or `.` for its existing
prepared working directory. Explain direct invocation in `examples/README.md`.
Regenerate the three example sources with
`python3 tools/check-gallery-examples.py --update`.

Use explicit inputs; no fallback path searches, executable-location discovery,
hidden working-directory changes, or runner rewrite. Prove the three defaults
work from the root, explicit inputs work from another directory, and existing
example outputs and cleanup behavior remain correct.

### C2. Documentation for behavior that already works

Correct `docs/src/guide/values.md` for indexed Array updates and NULL results
from wrong-tag pointer-shaped reads. Add a wildcard code/detail catch example
to the exceptions guide, using `Error.snapshot` for retained detail. Compile
and run the changed examples. Do not change working runtime behavior.

Correct and archive `plans/2026-09-06-wildcard-catch.md` as already implemented,
with current evidence and the completing documentation commit. Do not describe
`value is i32` as unsupported. Optional deprecated-site cleanup means only
`site/src/deprecated/`, and is not on the critical path.

### C3. String comparison

Gary accepted literal-only contextual conversion for `==` and `!=`,
symmetrically, preserving
raw pointer and identity comparisons. Dynamic C-pointer comparison has wider
NULL, allocation, and pointer-validity consequences and is not implied.

Reuse `_raw_string_to_string`, `convert_expression`, and normal
protocol comparison in `src/expressions.x`. Update the collections guide and
relevant language semantics. Prove the documented result, equal/unequal and
empty literals in both orders, single operand evaluation, and preserved
pointer/identity behavior. No new runtime equality implementation is needed.

### C4. Original lambda failures

Recover the exact original snippets and native diagnostics. Until then, mark
the report unverified and continue all independent assignments. Once a failure
reproduces, diagnose its actual owner, repair it narrowly, and prove native
compilation plus expected runtime output. Do not schedule a generic lambda
rewrite or claim the missing cases are fixed.

## Performance and generated output

### P1. Current baseline and candidate selection

Use current optimized compiler/runtime snapshots and unchanged programs.
Reuse `unittest/benchmarks/run-compiler-translation.sh`, relevant existing Var
benchmarks, and a full compiler/runtime translation workload. Record flags,
input set, repeated timings, output comparison, and a current native profile.
Separate instrumentation from timed binaries and cold from warm runs.

Rank remaining Var decode/conversion, expression-chain scans, Match binder
work, and collection lookup by measured cost. Source graph counts are leads,
not execution frequencies. Existing direct boxing is baseline, not a new win.
Do not promise the old percentage or calculator-to-C targets.

### P2. Runtime conversion and encoding

Own `lib/var.x`, `lib/varconvert.x`, and only the needed parts of
`lib/common.x`/`lib/dispatch.x`. Start with repeated source classification in
`Var.convert` and `Var.numeric_decode` if P1 confirms material cost. Pass an
already-established decoded value or metadata to a private operation rather
than redoing public boundary work. Extend constant boxing only where remaining
measured traffic and the existing representation justify it.

Preserve eight-byte representation, every numeric conversion, malformed-bit
rejection, error ordering/details, exact-tag identity, and wide-box lifetime.
Do not remove public validation merely because an internal caller knows more.
Reuse current Var/Varops suites and focused conversion probes. Keep a change
only with a demonstrated useful workload improvement and no behavior drift.

### P3. Expression and Match repeated work

After C3 releases `src/expressions.x`, eliminate repeated resolution/scanning
of the growing left subtree without assuming that a type annotation alone
proves context-independent binding. Ordinary parser-produced operands can
reuse established facts; macro-constructed ASTs must still bind correctly in
their current scope. Prefer direct producer/consumer reuse over global caches.

Separately, trace Match binder extraction/classification across statements,
transforms, and emission. Pass facts within the unit when that deletes repeat
work; do not add another pattern grammar or runtime matcher. Compare chain
scaling, full translation, generated semantics, macro rebinding, and lambda
capture behavior. Keep representation or cache design conditional on evidence.

### D1. Complete, minimal generated declarations

After B3, preserve consumer-visible properties such as `_Noreturn` and omit
declarations only when an included header actually supplies them. Reuse the
existing declaration/type owner and header contribution facts. Prove separate
owner/consumer compilation and serial/parallel agreement.

Broad declaration discovery remains a design assignment: establish forward
references, include order, and compile-time Lisp evaluation before replacing
synthesized prototypes with owner-header includes. Generated spacing is a
small optional cleanup, not justification for rewriting emission.

That design is complete in `plans/x2c-declaration-discovery-design.md`.
Forward function, imported macro/Lisp, local macro/Lisp, and include-cache
probes support retaining selective two-stage collection and native prototypes.
Eager Lisp evaluation would change the existing phase boundary; inferred
owner-header insertion has no demonstrated benefit sufficient to replace the
current contribution facts. The broader replacement is rejected on that
evidence, rather than left as unexamined implementation work.

### B4/B5. Faster development loop

After B1, let native scheduling complete any owned pending child instead of
waiting on the oldest. Reuse existing status, capture, and reporting ownership;
prove concurrency bounds, correct result attribution, and failure draining
with a controlled compiler wrapper, then measure real builds.

Independently, remove raw manifest comments/whitespace from the state seed in
`src/project.x`. Reuse lowered requests, ordered arguments, and actual input
dependencies rather than building a second semantic manifest serializer.
Prove comment edits reuse compilation while effective settings invalidate it.

Evaluate stage translation parallelism only after B3, using existing flags
first and measuring interaction with native jobs. Focused test selection stays
optional. No broadened readiness sequence is proposed.

The runner now accepts exact suite-name arguments through the existing suite
macro and harness owner. No arguments keep all 48 registrations in their
existing order; duplicate names run once and unknown names return status 2.
The full run still passes 743 tests / 18,227 assertions; reversed selection,
duplicates, unknown-only and mixed-known/unknown runs pass focused checks.
No Make target or publication requirement changed. Evidence:
`debug/unit-selection-results.json`, `debug/unit-selection-build.log`.

Stage evaluation is complete using a frozen copy of the current compiler,
75 source units, support artifacts, and the unchanged stage Makefile. Three
clean runs per combination produced these median seconds:

| Translation jobs | Native jobs | Wall | User + system CPU |
| --- | --- | --- | --- |
| 1 | 1 | 12.683 | 12.264 |
| 4 | 1 | 10.303 | 12.704 |
| 1 | 16 | 3.701 | 12.564 |
| 4 | 16 | 2.628 | 13.039 |

At the host's 16 native jobs, four translation workers reduce wall time 29.0%
for 3.8% more CPU time; the ranges are 3.676-3.714 and 2.622-2.707 seconds.
All 12 builds produce identical C/H bytes. The resulting compiler also
retranslates all 150 C/H artifacts identically with matching source paths.
Use the existing opt-in `make build X2C_FLAGS='-j 4'`; native Make jobs retain
their existing owner and defaults. One host's result does not set a new
cross-platform default. Exact stage invocations use
`make -f ../stage.mk -j16 X2C_FLAGS='-j 4' target` in an isolated stage directory.
Evidence: `debug/stage-jobs.json`, `debug/stage-jobs-selfhost.log`, and
`.context/stage-jobs.py`. This evaluation adds no gate or scheduler.

## Tooling and packages

### T1. Native debugging at source locations

After D1 releases generation, carry existing origins through emission and
formatting as C line directives. Reuse `Compiler.origin_location`; associate
macro output and synthesized cleanup with their owning source construct.
No new AST provenance system is needed.

Concrete recommendation: source mapping is an explicit opt-in, off by default,
available to build and standalone translation. With it enabled, C `__FILE__`
and `__LINE__` refer to the original x2c source; `-g` alone does not enable it.
Include the option in translation fingerprints. Gary accepted this
recommendation during the September 8 semantic discussion.
This is a documented compiler-output choice, not just debugger presentation.
Prove source breakpoints, ordinary stepping/backtraces, included files, macros,
and paths with spaces. Inspect one optimized build without promising exact
optimized stepping or reconstructed source-language values.

### T2. Native compilation database

After the driver scheduling edits, serialize actual
`Toolchain.compile_action` arguments with working directory, source, and
output. Collect actions before checking whether compilation is current.
Reuse `project_plan` for manifests. Do not parse verbose logs or fabricate
clangd commands for x2c syntax.

Prove direct/manifest/multiple-target builds, complete no-op output, and exact
argument preservation. This can ship independently of source mapping.

### T3. Package production and source distribution

After B1 and with exclusive driver ownership, lower package compilation and
archiving to current native actions. Produce the current public headers,
archive, and link-file layout; keep native dependency preparation in
`dependency.mk`. Have `packages/package.mk` delegate those actions, deleting
its duplicate build orchestration.

Use the existing source-distribution contract for the first milestone. Imports
still require `.x` sources. The source bundle carries `packages/<name>` and
the shared `package.mk`, `dependency.mk`, and `tools/deps.py` support under
`packages/`. Resolve support relative to those files and select an installed
compiler explicitly. Include these support files in this worker's ownership.
Allow dependency preparation to use an explicit `X2C_DEPS_DIR` without first
requiring a Git checkout; preserve the existing repository cache default.
Reuse the same download, checksum, preparation, and native profile operations.

Prove pure x2c, multi-unit, mixed C/x2c, and native dependency packages;
unpack a source package outside any Git checkout and prepare/build/use it
with an installed compiler and the distributed support files, without the
original checkout. Preserve actual native dependency flags.

Relocatable built installation is separate and needs Gary's distribution and
dependency-bundling choice. Its eventual proof must move the install prefix
and make the producer checkout unavailable; copied archives and headers alone
do not meet that promise. Defer registries and catalogue expansion.

### T5/T6. Shared frontend and semantic editor minimum

After B3, extract internal configured session/unit/result ownership into
`src/frontend.x`, deleting duplicated setup from `src/main.x` and the graph
adapter. Reuse tokenization, collection, parsing, diagnostics, Context, and
Type lifetimes. Keep printing and exit policy in adapters. Retain diagnostics
on unsuccessful parses until explicit close. First support sequential units;
process-global type and header caches do not permit an assumed concurrent API.

Prove existing graph/CLI parity, sequential lifetime correctness, and readable
failed-parse results without exiting an embedding caller. Keep this internal;
no supported public compiler-library compatibility promise is introduced.

The internal extraction keeps configured session and unit stages explicit:
start/tokenize, collect, parse, and close. CLI inspection remains between
those stages. Ordinary compiler-error recovery covers reading, tokenization,
and collection as well as parsing; unsuccessful units keep diagnostics until
close. Speculative parse scopes restore their previous diagnostic emitter.
The graph adapter must close failed units too. The source review and exact
owner boundaries are recorded in `.context/t5-frontend-boundaries.md`.

The editor followup starts with diagnostics, definition, and hover. Before
implementation, prove source spans and a request-owned unsaved-file overlay,
effective project/package settings, and cache isolation. Use fresh worker
processes for changed requests until cache invalidation is established;
serialization alone does not prevent stale header replay. Reuse the manifest
parser and return configuration errors instead of terminating the service.
Prove unsaved and included-file edits update results, imported names resolve,
malformed input retains diagnostics, and repeated requests release state.
Defer rename, completion, workspace indexing, and incremental analysis caches.

## Narrow language and library followups

After C3, adjacent C literals are a bounded feature: retain escape boundaries
and raw C-string typing, reuse existing literal construction, and keep percent
interpolation separate. Prove initialization, arguments, comparison, and
`"\x41" "B"` byte results.

Design array designators against existing field-designator and conversion
machinery, including positional continuation, nesting, and runtime-typed
elements. Lower `_Static_assert` through ordinary declaration emission and
let native compilation own constant-expression/assertion semantics.

Gary approved static Match binder types and arm-expression guards, implemented
by desugaring shorthand into the canonical explicit pattern language. Reuse
the matcher and normalization operations; do not build a parallel matcher.
Typed captures test the input type instead of converting mismatched values;
a mismatch tries the next arm. Evaluate a guard after matching; false tries
the next arm and errors propagate normally. Captures are local to the guard
and arm body. Finish the concrete syntax and core predicate lowering against
current source before implementation. Existing pattern guards already work.

Comparator/key sorting, SQLite, and bounded concurrent HTTP are application-
driven followups after current packaging is usable. Scope them from concrete
programs rather than copying every List operation to Array. Public API
deletion, matcher-oracle removal, and removal of optional tests remain outside
this plan.

## Decisions and completion

Only the dependent assignment waits for a consequential unresolved choice:

- C3: Gary accepted literal-only contextual comparison; ready to implement.
- T1: Gary accepted explicit opt-in mapping, off by default, with original
  source-location macro semantics; `-g` remains independent.
- Package delivery: Gary accepted source distribution for the first milestone;
  built installation and native dependency bundling remain deferred.
- Match: the desugaring architecture and type-checking capture semantics are
  approved. Complete the bounded source design before implementation.

C4's original examples have been recovered and reproduced. P1 determines
which performance candidates earn implementation. B3 begins with bounded
diagnosis. The rest of the ready work can proceed independently.

### Delivery record

- September 8: dbcd4dd expands the book's language summary, removes command-
  line/project entries from the From C adoption table, and keeps the landing
  page in two columns at widths of 640 pixels and above. The documentation
  gate and complete site build passed; GitHub Pages deployment succeeded.

- September 9: d5eba54 fixes the feature table label width. Its percentage
  inside a CSS clamp allowed fixed table layout to fall back to equal columns;
  the width now resolves from the viewport and stays between 96 and 120 pixels.
  Documentation validation and the site/book build passed.

### Current verification and next action

The first correctness batch shipped as bb3de5b. The final exact-tree gate
passed 743 tests / 18,227 assertions, 584 compiler fixtures / 1,361 artifacts,
self-host comparison, native boundary probes, raw-symbol validation, and the
book audit. The previous standalone-abort host stall cleared after reboot;
all four formerly hanging probes exited naturally. No host configuration
change was made. Evidence: `debug/post-reboot-correctness-gate-final.log`,
`debug/post-reboot-abort.log`, and `debug/post-reboot-fatal-probes.log`.
GitHub Pages deployment succeeded after publication.

The second batch shipped as 49d46e8:

- P1/P3: fixed compiler/runtime inputs, a warmup, and five measured runs per
  candidate give identical generated C/H. Resolving each growing binary
  subtree once reduces the 1,600-term median from 1.965s to 0.043s. Full
  translation remains effectively unchanged (3.773s to 3.802s). Existing
  macro, lambda, protocol, and String comparison fixtures pass. Logs:
  `debug/p3-comparison.json`, `debug/p3-focused.log`. A separate isolated
  Match classification candidate preserved all 148 output files but changed
  full translation by -0.07% and a Match-heavy workload by -0.49%, within
  noise; it was rejected. See `debug/p3-match-results.json`.
- P2: Var conversion reuses numeric metadata already established by its
  caller. Both candidates pass 54 tests / 5,993 assertions. Seven alternating
  measurement pairs show 25-34% lower numeric conversion cost; identity
  conversion is unchanged. Full-compiler profiles do not support a claim of
  overall compiler improvement. Evidence: `debug/p2-numeric-measurements.json`
  and `debug/p2-focused.log`.
- B4/B5: completion-any native scheduling and semantic manifest reuse pass
  all 97 CLI probes. Five paired native builds of 73 frozen C units reduce
  median wall time from 2.917s to 1.896s (35%), with 1.7% more aggregate CPU.
  Every object is byte-identical. Failure probes prove concurrency limits,
  child-specific output, stopped launches, and complete draining. Logs:
  `debug/b4-timing.json`, `debug/b4-b5-cli-boundary.log`.
- C4: the original nonfinal and parenthesized lambda programs now both
  compile and print 7. The regression includes explicit comma bodies,
  nested parentheses, macro callbacks, and captured Func arguments.
  Recovery evidence and exact source are in `.context/lambda-recovery.md`.
- D1: the existing prototype collector now also recognizes declarations
  supplied by the unit's own generated header. The header-cache probe passes
  and separate owner/consumer compilation retains `_Noreturn` under
  `-Werror=return-type`. Logs: `debug/d1-header-cache.log`,
  `debug/d1-native-after.log`. Broad owner-header discovery remains deferred.
- Match: concrete typed captures and expression guards pass mismatch,
  alternative retry, repeated captures, aliases, dynamic patterns, cleanup,
  errors, source macros, and canonical constructed macro probes. All 12
  focused fixtures / 29 artifacts pass, including Type-valued macro
  parameters resolved after ordinary substitution. Removing the shared
  provisional template-binding call reproduces a Var method lookup failure;
  the extracted existing owner is necessary. Logs:
  `debug/match-focused-family-final.log`,
  `debug/match-template-control.log`.
- T2: actual native compile actions supply opt-in
  `--compile-commands <file>`, including retained actions and manifest
  dependencies. Generated C is retained; failed builds leave the previous
  database unchanged. Exact arguments, empty graphs, retained objects,
  manifest dependencies, dry runs, and failure preservation pass. The full
  integrated driver suite passes all 110 probes. Logs:
  `debug/t2-probe-after.log`, `debug/t2-cli-tail.log`,
  `debug/wave2-cli-boundary-final.log`.
- T1: opt-in source mapping passes native builtin-location checks, source
  breakpoints, stepping, backtraces, includes, macros, cleanup, escaped
  filenames, and optimized inspection. Seventeen ordinary fixtures and
  fourteen mapped native runs pass. The combined CLI case also exposed a
  preexisting forward-binding bug: two untyped references could invent a
  shadow name without a declaration. Shadow renaming now requires the
  visible declaration's existing type fact. Logs: `debug/t1-focused.log`,
  `debug/t1-final-native.log`, `debug/t1-final-debugger.log`,
  `debug/t1-combined-before.log`.
- T3: explicit dependency caches no longer require a Git checkout; the
  existing 11 dependency tests now run outside Git and pass. Shared Make
  support resolves beside its own files. Native compilation and archiving
  now use one driver request. An unpacked bundle builds and runs pure,
  multi-unit, mixed C/x2c, and yyjson programs with a separate compiler
  installation after deleting the bundle producer. Unchanged builds retain
  archive and consumer mtimes; native-header changes rebuild the affected
  object and archive. Logs: `debug/t3-source-bundle-driver.log`,
  `debug/t3-warm-package.log`, `debug/t3-header-reuse.log`.

GNU Make 4.4.1 is available through Homebrew. Put its `libexec/gnubin`
directory first in PATH. The coordinator owns shared regeneration, authored
and generated review, current-main integration, the exact-tree publication
gate, and delivery. No pending work in this batch requires user input.

The publication run established identical bootstrap and stages 0-2 after
refreshing the declaration cleanup. Nine C fixture snapshots required only
removing declarations supplied by their own headers; each removal was reviewed
and its expectation regenerated through the fixture runner. Full validation
passed 743 tests / 18,227 assertions, 587 fixtures / 1,367 artifacts, 110 driver
probes, 420 required raw-symbol translations, and the book audit. Current main's
Code of Conduct addition was integrated and the final tree revalidated before
publication. Site/book build also passed. Evidence:
`debug/wave2-gate-integrated.log`, `debug/wave2-site-build.log`.

The final batch implements T5's shared configured frontend and retained-error
lifetime, T6's source spans/overlays/editor adapter, adjacent C literals,
declaration-position `_Static_assert`, and bounded designated initializers.
Initializer scope covers direct array designators, explicit nested braces, and
correct conversion after a named-field designator. General chained designator
brace elision remains outside this bounded implementation; it cannot assume a
new C constant evaluator.

- T5: 22 CLI comparisons preserve content; two symbol maps differ only in
  iteration order. The graph suite and sequential success/failure, retained
  warnings, emitter restoration, and Context/Type cleanup probes pass.
  Existing persistent header-cache retention reproduces in the pre-extraction
  graph frontend; it is separate from unit cleanup. Logs:
  `debug/t5-cli-parity.log`, `debug/t5-lifecycle.log`,
  `debug/t5-old-lifecycle-build.log`, `debug/t5-graph-tests.log`.
- T6: nine native worker tests pass, including new and unsaved sources,
  lexical definitions and hover, included-file edits, package aliases,
  project configuration, macro failures, transaction rollback, and native CPP
  locations. The extension passes eight transport/provider tests and both
  grammar fixtures; the isolated source-view probe verifies empty overlays.
  Cancellation terminates native worker descendants before
  removing snapshots. Version 0.2.0 is packaged for repository delivery; no
  Marketplace publication or installation was performed. Logs:
  `debug/t6-worker-tests-final.log`, `debug/t6-extra-final.log`,
  `debug/t6-sourceview.log`. The worker is internal and checkout-bound.
  Removing the two transaction metadata transfers in an isolated control
  loses an imported declaration's definition; the candidate retains its
  exact header span (`debug/t6-control-result.log`).
  Native CPP refuses consumed unsaved input. Included documents need an
  explicit target input or direct configuration, and declarations skipped by
  the compiler's existing shallow collection have no invented definition.
- Language followups: 18 fixtures pass 47 artifacts. Adjacent literals retain
  escape boundaries; assertions remain native C declarations. Initializers
  preserve String/Var conversions, inferred sparse dimensions, nested braces,
  and native rejection of invalid designators or const assignment. Deferred
  writes stay within the native array bounds, including excess values that C
  warns about and discards. Native array typedef indexing now works while
  custom `getindex` retains priority. One existing C snapshot changed to the
  reviewed zero declarations and bounded assignments. The book sample prints
  `5 6 8 9 AB`. Evidence: `.context/narrow-language-followups-design.md`,
  `debug/wave3-book-examples.log`.

The complete site/book build passes in `debug/wave3-site-build-final.log` and
the documentation audit covers 107 files. Native editor tests pass again
against the final read API (`debug/t6-worker-tests-delivery.log`). Its output
pointer retains volatile qualification required by exception-frame locals;
all four affected native modules compile with `-Werror` in the isolated probe.
The existing unit executable now links the source-view dependency, and the
existing documentation module check uses the stable section heading instead
of a literal module count. No validation requirement was added.

The final batch shipped as e6efc74 after the exact-tree publication gate
passed: 743 tests / 18,227 assertions, 590 compiler fixtures / 1,373 artifacts,
110 driver probes, 425 required raw-symbol translations, self-host comparison,
and the 107-file documentation audit. The final build has no new qualifier
warnings. Evidence: `debug/wave3-gate-delivery.log`. The complete site/book
build and the packaged extension were reviewed before delivery.

The delivered implementation is validated, but the completion audit found
remaining work in the original approved scope. Chained designators and brace
elision were bounded out by implementation choice, not by Gary's approval;
they are being completed through the existing initializer owners. Sorting and
bounded HTTP now have concrete callers and focused proof, and await integrated
publication. SQLite has a concrete task list and example sketch in
`plans/x2c-sqlite-package.md`; its new public package scope awaits Gary's
answer under `packages/AGENTS.md`. Relocatable built installation and native
dependency bundling remain deferred by the accepted distribution decision.
Editor completion/rename/indexing and incremental semantic caches remain
outside the accepted editor minimum.

### Completion audit work awaiting delivery

- B4/B5: the stage translation evaluation and optional suite selection above
  are complete. Neither changes the default build or publication sequence.
- D1: the broader discovery design records source and executable evidence in
  `plans/x2c-declaration-discovery-design.md`.
- T3: the package guide now gives the exact source-bundle production recipe.
  `plans/x2c-source-package-proof.md` records successful pure, mixed, and native
  dependency builds with reads of both original checkouts denied. This uses
  an isolated native compiler fixture, not the optional APE installer.
- Sorting: `Array.sort_with` uses stable merge sorting with borrowed `Func`
  callbacks; `sort_by` computes each key once and preserves ties. Both commit
  only after successful callbacks. List wrappers reuse those operations.
  Word counting and graph component ordering exercise the APIs. The Array
  and List suites pass 54 tests / 480 assertions, including callback failure,
  cleanup, ties, nested sorting, and uneven merge tails. Gallery and graph
  checks pass. Evidence: `debug/sorting-suites.log`,
  `debug/sorting-counting-parity.log`, `debug/sorting-graph-tests.log`.
- HTTP: libcurl batches use the existing transfer owner, a caller-selected
  concurrency bound, input-order results, and ordinary response/error access.
  Both applications use the batch API. Local checks cover actual concurrency,
  completion order, errors, timeouts, empty/broadcast bodies, option inheritance,
  and handle reuse. All 29 wrapper tests / 203 assertions, two raw tests /
  16 assertions, applications, and Lisp checks pass. Evidence:
  `debug/libcurl-empty-upload-final.log`. Package acceptance status is unchanged.
  The combined compiler/runtime candidate also passes the existing
  `make packages-check` across all seven packages, applications, and Lisp
  adapters (`debug/completion-packages-check.log`).
  The full unit runner passes 747 tests / 18,282 assertions on the same
  candidate (`debug/completion-units.log`).
- Initializers: chained designators and brace elision now use one subobject
  walk for conversion and deferred assignments. Native object sizes preserve
  macro-dependent bounds without a second C constant evaluator. Remaining
  compound-literal cases are in implementation; final proof is pending.
- SQLite: scope is proposed in `plans/x2c-sqlite-package.md`. It has no client
  implementation yet and is not claimed complete or accepted.

## Plan review

Existing producers establish canonical String/List identity, validated numeric
encodings, typed native action arguments, lowered project requests, parsed
Match captures, retained Error lifetimes, and source-origin ancestry. Consumers
reuse those facts. Typed expression annotations alone do not establish that
macro syntax is bound for every later scope, and link argument text alone does
not establish unchanged resolved libraries; this plan preserves both limits.

B1 removes unsound executable reuse; B2 repairs the existing evidence owner.
C1 uses the existing fixture runner; C2 documents existing operations. P2/P3
delete repeated work while preserving public boundaries. D1 reuses declaration
ownership. T3 deletes duplicate package build actions; T5 deletes duplicate
frontend setup. Necessary lasting additions are source-location emission,
actual-command serialization, internal frontend lifetime ownership, and editor
input/transport handling. No general registry, cache framework, second linker,
second manifest parser, or parallel AST validator is proposed.

Compiler edits use Match and canonical literal templates and ordinary binding,
conversion, scope, and emission operations. Runtime changes preserve actual
identity and lifetime representations. This keeps implementation direct x2c
rather than importing an unrelated compiler framework.

No new dedicated validator or diagnostic is planned for the ready fixes.
Existing malformed-Var checks remain because they protect public behavior and
safe extraction. Negative coverage, when needed, protects that established
behavior, truthful validation reuse, native child failure handling, or the
editor's non-terminating request boundary. A false static assertion belongs
to native compilation. No fixture is justified solely by earlier rejection.
