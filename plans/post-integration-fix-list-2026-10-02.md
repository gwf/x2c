> Status: active
> Integrated backlog, reconciled 2026-10-02 against dev `2c8ddfb3`, with
> the named-macro catalogue spike reviewed against its `1b71a410` base.
> Implementation authorized 2026-10-02 through orchestrate-x2c-work.
> Sol 6.1 workers provide private handoffs; this session integrates and delivers
> coherent batches directly to dev. Three prior repairs are already delivered.
> Open items retain their evidence limits and unresolved compatibility choices.

# Integrated post-integration fix list

The first work is correctness: unfinished static initialization, stale linked
meta code, unlowered match expressions, and missing literal sequencing. The
largest measured waste is constant catch-pattern rebuilding and quadratic
translation, and catalogue import/native compilation cost. The named-macro
spike now supplies the leading catalogue replacement, subject to its exposed
literal defect and remaining validation. Small Lisp, Atom, and symbol-owner
changes remain promising independent reductions.

This list accounts for all 35 numbered findings and all 13 pre-existing
findings in the supplied review, plus this workspace's deeper waste review.
There are 41 open scopes below, including investigations and unresolved
contracts, and three completed repairs. One scope can cover several source
findings; a shared owner does not make their acceptance cases interchangeable.

## Evidence and provenance

- External review, identified below as **X01-X35**, and its pre-existing list
  in order, **B01-B13**:
  [review and probe index](/Users/gary/Git/x2c/.claude/worktrees/awesome-zhukovsky-fd5a3f/.context/post-integration-review-2026-10-02/README.md).
  Its paired baseline is `00536cc8`, original review tip `cd9544f1`, with
  updates on `1b71a410` and PR #98's head `8f95ec33`.
  The later attachment described as an architectural review is byte-for-byte
  identical to this source; it adds no separate findings or evidence.
- This workspace's review, **D01-D09** as mapped at the end:
  [report](../.context/deep-review/report.md),
  [runtime evidence](../.context/deep-review/runtime.md), and
  [compiler evidence](../.context/deep-review/compiler-waste.md).
  Its original baseline is `cd9544f1`; its delivered repair tree is `1b71a410`.
- Reconciliation evidence:
  [compiler mapping](../.context/deep-review/reconcile-compiler.md),
  [tooling mapping](../.context/deep-review/reconcile-tooling.md), and
  [four probes on merged dev](../.context/deep-review/integrated-fix-list-probes.json).
- Named-macro catalogue spike, **S01-S03** below:
  [spike record and scripts](/Users/gary/Git/x2c/.claude/worktrees/awesome-zhukovsky-fd5a3f/.context/post-integration-review-2026-10-02/spike/README.md)
  and [our reconciliation](../.context/deep-review/spike-review.md).
  This is unpublished scratch work based on `1b71a410`, before PR #98.
  Saved build logs and source counts were inspected; timings were not rerun.

**Current** means reproduced during this reconciliation on merged dev
`2c8ddfb3`. **Rerun** means a Sol reviewer reproduced it using `1b71a410`;
those probes do not claim to use the newer compiler. **Source** means the
mechanism or document was checked, without rerunning its behavioral claim.
**External V/R** retain the supplied review's distinction: V was rerun by its
session owner; R was reported by its reviewer. **Measured D** refers to our
earlier operation counts or measurements, not a new performance benchmark.

PR #98 merged as `fcfaff40`, with generated updates through `2c8ddfb3`.
The four Current probes used that integration checkout's built compiler with
temporary outputs. This workspace remains on `1b71a410`; the consolidation
does not claim a local rebase or a new full gate.

Some external headings overstate historical regression: X14-X16 already
emitted the same C at the paired base, but violate the new sequencing promise;
X18 also failed there. X08-X12 concern incomplete newly accepted syntax.
These are current defects or gaps, not all formerly working programs broken
by integration. B items predate the range and remain explicitly included.

## Priority and metric policy

P1 means crashes, wrong output, unsafe lowering, or a large reproduced waste
regression. P2 means other correctness, compatibility, workflow, or worthwhile
performance work. P3 means small cleanup or drift. **Investigate** and
**decide contract** entries are not implementation-ready deletion proposals.

Prioritize removing redundant work and reusing the existing owner. Compare
runtime, compiler build time, total LOC, and source clarity on the same
behavior. Expected improvements below are hypotheses until a replacement is
measured. Correctness repairs can require more code or necessary sequencing;
do not disguise that tradeoff as an all-metric gain. Preserve cheap constant
paths while repairing dynamic paths.

## Correctness and language integration

### F01. P1 - Unwind an unfinished static initializer on lexical exits

**X08; Current.** `stmt-expr-static-exit.x` prints `first -1`, then aborts on
its second call with recursive/cyclic initialization. An outward `break`
leaves the guard held and an abort record registered. The later-raise bus
error remains External R. This is separate from completed C01.

Owner: `src/cleanup.x`, `src/emit.x`, existing static/exception cleanup.
Make existing nonlocal-exit cleanup release unfinished initialization; retain
legal lexical transfers. Check break/continue/return/outward goto followed by
retry, then a caught raise, successful once-only initialization, stable
addresses, and existing threaded/const/array cases. Do not add a parallel
cleanup system.

### F02. P1 - Preserve statement-expression types and final values

**X10-X12; Rerun.** An unproven optional reference is typed as T while emitted
as T*, an expression-bodied lambda fails to convert a nested return to Var,
and a final destructuring assignment loses its List value. All three produce
bad native C; the optional-reference address-comparison claim is External R.

Owners: `src/expressions.x` final-value typing, `src/lambdas.x` return context,
and `src/transform.x` destructuring. Use ordinary reference checks, callable
return conversion, and the assignment's existing value contract. Check
proven/unproven references, nested returns with defers, and one evaluation of
the destructuring RHS. Each subcase must pass independently, without native
type warnings.

### F03. P1 - Lower expressions inserted into match-arm patterns

**B01; Current.** `match-arm-string-literal.x` builds, then dies with SIGBUS.
A String-taking call receives an unlowered native string from `${...}`.
Owner: `src/transform.x` match-pattern normalization and ordinary literal
lowering. Route inserted expressions through that owner before emission.
Check plain/interpolated strings, call arguments, and canonical Lists built
by Lisp. Preserve pattern meaning and source locations. Coordinate with F04;
repairing evaluation order alone does not repair missing conversion.

### F04. P1 - Apply the literal sequencing contract to every entry path

**X14-X16; Rerun/generated C.** Custom converter casts, native object-like
macro reads through casts, raise details, and match patterns can remain
unsequenced C call arguments. One native-macro probe warns about unsequenced
counter modifications. A local run printing the expected order is not proof.

Owner: `src/transform.x` literal conversion/effect classification and the
raise/match callers. Classify actual converted effects and reuse the ordinary
ordering owner. Check array/list/map/string, cast conversions, raise details,
and pattern interpolation for left-to-right, exactly-once evaluation and
error order. Inspect generated sequencing. Preserve F05's constant path;
blanket temporaries fix one metric by harming others.

### F05. P1 - Recover static catch patterns without needless temporaries

**X02; External V + Source.** Nested constant detail Lists make catch sites
transient and rebuild them at each entry: 300,000 entries took about 999 ms
versus 12.3 ms at the external base. `_part_order` treats nested construction
as state-changing; resulting statement expressions defeat
`Compiler.match_pattern_value`. Compiler-generated bare-string boxer callees
also miss builtin-converter recognition and can get unnecessary temporaries.

Owners: `src/transform.x`, `src/expressions.x`, `src/compiler.x`, catch lowering.
Preserve constant-pattern recognition through ordering, using existing facts.
Check one preparation for nested constant catches, refresh for dynamic
patterns, cheap cached boxers, and custom/shadowed converter order. Mutable
Array/Map construction must not become a constant. Runtime Match spelling
work in F36 is a separate cost.

### F06. P2 - Transform each ordered List chain once

**X03; External V + Source.** A 2,000-part List translated in 4.04 s versus
0.18 s. `_cons` and `_append` each invoke `_ordered_list` over the remaining
suffix, and the driver revisits suffix nodes.

Owner: `src/transform.x`. Give the chain one conversion/ordering traversal,
preserving the ordinary transform contract. Check linear node visits with
increasing sizes, dynamic elements, splices, final tails, constant prefixes,
conversions, and exceptions. This may share F04/F05 work but needs its own
scaling proof; F39 is a different quadratic loop.

### F07. P1 - Remove repeated cleanup subtree scans with depth safety

**X04; External V + Source; large crash External R.** A 5,000-term expression
containing a Func call/literal took 2.00 s versus 0.17 s. The report's
40,000-term case segfaulted after 46 s. Five cleanup operations call a full
`_holds_statements` walk at each expression level.

Owner: `src/cleanup.x`. Traverse efficiently while retaining which expressions
actually need cleanup; simply deleting the guard can introduce deep recursion.
Check linear visits and successful deep-chain translation with ordinary stack
settings, plus a plain-chain control. Preserve statement-expression transfers,
defers, static initialization, and exception-local handling. Coordinate F01;
do not erase distinct cleanup analyses merely because they walk the same AST.

### F08. P1 - Delay linked-meta reuse until forward dependencies are known

**B04; Current.** `linked-meta-forward-callee.x` prints `integer 1 0`:
compile-time execution uses a stale shipped callee while runtime uses its
edited definition. The ordinary earlier-defined callee fixture passes.

Owners: `src/parse.x` definition hashes and `src/meta-native.x` linked
selection. A missing dependency hash must not establish equivalence before
the later definition is known. Use the existing definition/dependency owner.
Check forward and earlier-defined edited callees, unchanged linked reuse,
and PR #98's initialized-static/table-edit fallback. C03 does not close this.

### F09. P2 - Preserve native-header callee bindings in templates

**X05; Rerun.** A template calling native `time` is falsely rejected if its
caller has a local `time`; paired external cases also cover strlen/free/
exit/fputs. Owner: macro free-name binding and ordinary shadow renaming in
`src/expressions.x`. Preserve the native declaration's binding without
capturing the caller's local. Check present/absent same-spelling locals,
closed/open macro globals, and native names not declared in x2c source.

### F10. P2 - Bind nested macro declarations before resolving their uses

**X17-X18, B02; Rerun, some forms External R.** Same-block caller locals can
cause false free-name errors; nested forward declarations remain untyped for
methods and other typed forms. A Name argument can instead bind to a macro's
own forward local and silently lose the caller's assignment.

Owner: macro expansion binding and call-site Name identity. Preserve identity
through nested declarations; defer typed operations until their binding is
available. Check methods, foreach, $let, literals, local macros, repeated
expansions, and same/absent caller spellings. B02's intended Name semantics
are already an open design decision; resolve that contract before changing
it. Coordinate F16 without treating all failures as one reproduction.

### F11. P2 - Use one actual type identity for tag methods and their display

**X19-X22, B10; Rerun for lookup/binding; Source/External R for displays.**
`struct T` cannot bind a `T &` method; an unrelated global named like a tag
can create a spurious method owner. A free `struct_<name>` function can win
over the typedef method. Type descriptions/completion omit tag methods, and
the book omits the rule.

Owners: `_tag_typedef`/method binding in `src/expressions.x`, meta description,
REPL completion, and the book. Use a real typedef/aggregate relationship,
preserve direct/delegate precedence and ambiguity behavior, then reuse it
for display. Check struct/union, renamed typedefs, local/global tags,
by-value/pointer/reference first parameters on tag lvalues, and unrelated
same-spelling variables. Pointer-receiver lookup remains a separate decision.
Settle the generic `struct_` namespace behavior explicitly; coordinate F17's
qualifiers and document the resulting rule without expanding unrelated APIs.

### F12. P1/P2 - Restore REPL reference parity and truthful syntax handling

**B06, X13; Source + External R.** The REPL passes a pointer as a `T &`
receiver and returns garbage; it routes statement expressions into dynamic
Func application and refuses them for the wrong reason.

Owner: `commands/repl/repl-lower.x` and argument preparation. First reproduce
reference results, mutation, and refusals against compiled code, then reuse
ordinary reference preparation. For statement expressions, distinguish an
accurate unsupported-form refusal from full evaluation support. The latter
is a capability decision and needs ordinary block/local/final-value parity;
do not present a better refusal as complete support.

### F13. P2 - Remove the float helper collision and preserve NaN behavior

**X07; Rerun. X33; Source + external semantic probe.** `_box_float` is exposed
through `lib/common.x`, colliding with a user's function. Its promotion through
`Var.new(<f32>, x)` is necessary to retain established signaling-NaN quieting.
The signaling-NaN promotion repair already exists; its specific regression
test is missing. The helper-name collision remains open.

Use the existing scalar-family definitions to avoid the incidental helper
name, retaining float.var/str/repr and implicit-conversion behavior. Add one
meaningful case to existing Var tests using memcpy-created signaling bits and
ordinary/quiet controls; establish that it catches the rejected direct-boxer
substitution. Do not invent a new cross-platform NaN payload ABI. The stale
plan claim belongs to F27.

### F14. P2 - Rename the runtime launch record to JobLaunch

**X06; Rerun.** Importing `lib/process.x`, including through scripts, conflicts
with a user's `Launch` type. This export was deliberate for Job embedding.
Gary selected `JobLaunch` on 2026-10-02, preserving the embedded layout and
restoring user-defined Launch names. Do not retain a Launch alias, which would
preserve the collision. Update source consumers and docs and check process,
Job/script behavior, layout, and collision programs. Callers explicitly naming
the newly exposed runtime type must use JobLaunch; this compatibility choice
is authorized.

### F15. P2 - Normalize constructed strings before concatenation caching

**B05; Rerun.** `literal-string-add.x` emits invalid C when an
`x2c_literal_string` result is added to a constant string. Owner:
`src/expressions.x` string lowering and constant caching. Normalize canonical
constructed segments through the ordinary string owner; preserve macro-built
syntax without origin authentication. Check both operand orders, interpolation,
constant folding, and ordinary literal concatenation.

### F16. P2 - Type Func arguments after an Expression macro hole is filled

**B08; External R.** A Func call accepting an Expression macro hole reportedly
builds and aborts with bad-types carrying `(macro-expr)`. A reconstructed probe
hit a different earlier static-lambda refusal, so this is neither independently
reproduced nor refuted. Recover the exact source before editing.

Owners: `src/expressions.x`, `src/callables.x`, substitution/typing order.
Test the filled argument against its direct expression equivalent, including
conversion and effect order. Coordinate F10's delayed binding analysis rather
than adding a validator that rejects legal constructed syntax.

### F17. P2, partly decide contract - Preserve reference and const meaning

**B03, B09; Rerun/generated C.** A local `T &name = lvalue` becomes a pointer
instead of an alias; the book specifies references for parameters. Aggregate
const can disappear on field/delegate access, allowing a mutating reference
method with a native discarded-qualifier warning. The optimized probe did not
establish reliable runtime mutation and must not be cited as doing so.

Owner: declaration placement and member/receiver qualifier propagation in
`src/expressions.x`. Decide whether local references are supported aliases or
an unsupported declaration placement. Carry aggregate qualifiers through the
existing checks. Verify parameter references, const/volatile fields and
delegates, and deliberate mutable access. Coordinate F11.

### F18. P2 - Let warnings compose with compile-time begin sequencing

**B11; Rerun.** `(begin (x2c.diagnostic.warn ...) form)` emits the warning,
then fails with void-op; analogous let/cond composition works. Owners:
`src/meta-sdk.x`, `etc/init.xlisp`, Lisp sequencing/value transport. Settle
whether warning returns an ordinary nil value or begin accepts discarded
void results, using the existing contract. Preserve final form, diagnostic
origin/text, and intentional void rejection where an actual value is needed.

## Diagnostics, commands, and delivery

### F19. P2 - Report generated protocol errors at their triggering source

**X23; Rerun.** The postfix probe reports EOF 30:1 instead of `value++` at
26:3. Owner: `src/protocol.x` generated helper binding. Carry the triggering
origin through ordinary binding; do not add an earlier type validator just
for location. Check prefix/postfix failures and successful updates.

### F20. P2 - Keep catalogue diagnostics visible to existing lint rules

**X24; Rerun.** A direct raise is flagged while equivalent `$func.error` is
silent. External advisory findings fell 27 to 4; that total was not rerun.
Owner: `commands/lint/validation.x`. Recognize established catalogue contracts
at the existing rule owner. Test direct/catalogued pairs and user-defined
returning causes; a macro name ending `.error` alone proves nothing. Keep
advisory counts advisory and avoid forcing the historical total as a golden.

### F21. P1 - Handle lint input failures at the command boundary

**X25, B07; Rerun.** `-`, a missing file, and format-check on a missing file
all abort with uncaught not-found. Owners: both read paths in
`commands/lint/x2c-lint.x`; graph already has a relevant error boundary.
Share ordinary read-error handling, print useful stderr, and return normal
failure. Decide whether `-` is unsupported usage or a normal file failure;
stdin support is not implied. Check read/permission failures, `-- -`, ordinary
and format modes, and multi-input behavior without changing shared Error causes.

### F22. P2 - Admit the valid shared hook at an absolute checkout path

**X26; Source/current path observation + external refusal.** Context setup
rejects an absolute main-checkout hook path even though its executable policy
matches the tracked hook and discovers the pushing worktree correctly.
Owner: `tools/agent_context.py` hook admission. Recognize supported equivalent
policy while refusing stale/unrelated/non-executable hooks. Preserve user
configuration. Validate in isolated repositories with relative and absolute
paths and worker push restrictions. C02 fixes overwriting, not this refusal.

### F23. P2 - Make documentation generation and gate selection agree

**X27; Source + external isolated probe.** Book edits stale generated llms
texts and fail doc-check; regenerating those texts selects the code gate.
Owners: `tools/land-dev`, `tools/integrate-dev.py`, existing generated-doc
classification. Refresh docs through the existing path and classify their
outputs consistently. Check book + generated texts selects doc-check, while
source changes still select agent-pr-check. This removes redundant build work;
it must not add or expand a gate.

### F24. P2 - Make documented submission notes compatible with cleanliness

**X28; Source + external fresh-clone probe.** Guidance writes
`.context/submission/`, but submit rejects untracked files and the shipped
ignore policy lacks that path. Local excludes hide the mismatch on some hosts.
Owners: workspace-note guidance/ignore policy and submission checks. Choose
an appropriately ignored note path; retain rejection of unrelated untracked
source. Validate the documented flow in a temporary fresh repository.

### F25. P3 - Clear the active failure reason after successful integration

**X29; Source + external records.** Gated/landed transitions can retain an old
conflict/publication reason. Owner: `tools/integrate-dev.py` state transitions.
Clear the current reason on success while preserving existing attempt logs.
Check failure -> gated -> landed reconciliation in existing integration tests;
do not add a second status mechanism.

### F26. P2 - Preserve publication lock exclusivity during stale recovery

**B13; Source + external coordinated race probe.** One waiter can delete a
new holder's directory after reading an old dead PID. Fast-forward push still
prevents wrong-tip replacement; duplicate gates and conflicting work remain.
Owner: `tools/land-dev`; prefer the existing kernel-lock pattern in
`tools/integrate-dev.py` over a new reclamation protocol. Use two local
processes and temporary state to verify exclusive admission, holder exit,
and stale-waiter scheduling. No real lock, queue, gate, or network is needed.

### F27. P3 - Reconcile landed plans and the shared-cause book table

**X30, X33's plan drift, B12; Source.** Catalogue/value-reference/self-expression
records still describe pending work or pre-repair float equivalence. The
shared-cause table omits call-stack and interrupt. Update status/index against
landing evidence, retain genuinely open work and historical authorization,
record float promotion, and add the two documented causes. Archive only
completed plans. This consolidation records the work; it does not silently
close those other plans. Use ordinary documentation validation.

### F28. P3, decide contract - Catalogue operand-count inconsistency

**X31; Source + external misuse probes.** Eight of fourteen dispatchers lack
count checks; extra arguments can disappear and missing arguments reach
void-op. The external audit found zero mismatches in 196 current call sites.
No current correct invocation is shown to fail. Determine the intended call
contract during catalogue work. Earlier/more-specific rejection alone does
not justify eight validators or a new framework. If a uniform contract is
chosen, use one existing owner and preserve all valid diagnostic payloads.

### F29. P3 - Consolidate MachineBuilder release code compatibly

**X32; Source.** There are two identical release bodies, in drop and cleanup;
free forwards to drop. The report's three-copy wording overcounts duplication.
Owner: `lib/machine.x`. Give release work one implementation while retaining
exported init/drop/free/new/cleanup behavior unless separately changing its API.
Check default state, allocation-free construction, shallow backing-array
release, and explicit/automatic cleanup in the existing machine tests.
No material runtime or build improvement has been established.

### F30. P3, investigate - Package method source spellings

**X34; Source + external observation, no demonstrated user failure.** Generated
interfaces expose `libuv__UvTcp.close`; C ABI/headers and package tests remain
unchanged. Owners: method spelling in `src/parse.x` and package projection in
`src/collect.x`. First inspect actual documentation, diagnostics, completion,
graph/editor and alias consumers. Repair the existing source-name projection
only if a public contract is lost; do not change native identity for aesthetics.

### F31. P3 - Remove redundant command argument conversions

**X35; Source + external build warnings.** Two graph and three lint sites
call `.list()`/`.array()` where the destination already converts; one lint
site predates the range. Remove only proven redundant calls, preserving the
actual destination container and ownership. Focused command builds and
existing argument smoke cases should keep output and lose those warnings.
This can accompany F21 but is not the cause of its crash.

## Remaining waste and measurement

### F32. P1 - Replace compiler catalogue dispatch with ordinary named macros

**X01, remaining D05; external timing + Source + Measured D.** C03 removes
repeated Map construction. Import reparsing, cached Macro AST construction,
large generated C, and startup work remain separate costs. External three-run
src translation was 8.89/9.06/8.96 s at its base, 17.38/17.51/17.86 s at
`1b71a410`, and 17.92/18.37/18.01 s at the PR head. Import-only was 0.39 s
on both latter compilers versus 0.08 s for a plain unit. These are attributed
comparisons, not our quiet-host measurements on the merged tree.

The merged bootstrap retains 52,480 lines / 2,101,284 bytes of linked-meta C
versus 52,479 / 2,101,197 before C03. Historical native compile was about
6.6-8.9 s versus about 0.3 s before the catalogue, across the two reviews;
their baselines and timing setups must not be conflated. External startup
was about 12.4 ms versus 8 ms, with binary growth about 2.60 to 3.39 MB.
Before C03, startup built the linked literal/Macro graph, not necessarily the
Map: our zero-expansion unit invoked the old Map factory zero times.

**S01 now supplies a concrete leading replacement.** The scratch conversion
replaces all 269 `$report(c, "key", ...)` sites with ordinary named Statement
macros. All 254 rows are used; 256 definitions are placed in 19 consuming units,
with two rows duplicated across units. It deletes the compiler Map catalogue
and its dynamic key lookup/dispatcher. The authored patch exactly matches the
scratch checkout, and in-memory replay confirms all row bodies/call migrations
apart from the 50 explicit interpolation workarounds described in F41.

| Measurement | Base `00536cc8` | Dev `1b71a410` | Named-macro spike |
| --- | ---: | ---: | ---: |
| Clean stage-1 build, saved log | 10.04 s | 24.97 s | 15.54 s |
| Translate src units, reported | 8.7 s | 17.3 s | 10.8 s |
| Translate linked-meta, reported | 0.32 s | 2.18 s | 1.46 s |
| Compile linked-meta C at O2, reported | 0.33 s | 6.73 s | 2.27 s |
| Compiler startup/version, reported | 7.9 ms | 12.0 ms | 9.5 ms |
| Compiler binary bytes, read from disk | 2,596,624 | 3,394,688 | 2,941,328 |
| src .x + .xmacro physical lines | 47,583 | 52,850 | 50,754 |
| Generated linked-meta.x lines | 790 | 4,020 | 2,080 |

The spike cuts the recorded clean build about 38%, translation about 38%,
linked-meta native compilation about 66%, startup about 21%, and binary size
about 13% relative to its dev baseline. These are prototype results, not
independent repeated timings or measurements after PR #98. Total source falls
2,096 lines: **156 authored and 1,940 generated**. This is not 2,096 lines of
hand-authored machinery removed. Application runtime was not benchmarked.
Generated linked-meta C in both scratch stages is 22,641 lines / 906,176 bytes,
versus 52,480 / 2,101,284 after PR #98; equal size counts do not establish
stage equality.

Recommended scope and order:

1. Fix F41 through ordinary literal binding/caching, so all rows retain their
   original string spelling and the 50 workaround wrappers disappear.
2. Migrate the compiler's fixed diagnostic templates to ordinary named macros
   near their owning operations. Preserve messages, categories, notes, token
   fallback, capture identities and evaluation. Keep forwarded diagnostics on
   the existing report_error owner. Remove only the obsolete compiler table,
   dispatcher/imports and their generated copies; retain PR #98's general
   initialized-static support used by other code.
   Named closed macros capture definition-site bindings, whereas Macro values
   rebind stored references when applied; body-text parity alone does not
   prove binding parity. Check free names/types, forward declarations,
   shadowing, introduced locals, and definition/call order explicitly.
3. Resolve the two shared rows explicitly: `parse.alias.name` and
   `parse.package.member` are duplicated in the spike. Prefer a small shared
   definition where appropriate without restoring a whole-catalogue import;
   check the cost and binding tradeoff. The spike's underscore spelling and
   bulk insertion at import sites are prototype choices, not required style.
4. Use a checked row/call inventory and source-aware edits. The spike scripts
   rely on regexes and current formatting, so they are not a reusable migration
   guarantee. Recheck all names/captures/call operands, and compare all 254
   templates rather than relying on the subset reached by fixture execution.
5. Adapt `error-report-literals` to the replacement owner while preserving its
   direct-versus-template message, interpolation, nested-note and local-value
   checks. Preserve needed cross-unit literal coverage independently of a
   deleted compiler dispatcher. Coordinate F20's lint recognition with the
   new representation. Existing ordinary macro binding should own argument
   contracts; do not recreate table dispatch solely to retain private syntax.

The saved stage-1 log contains --fatal-warnings, -Werror, and rc=0. Stage 0/1
builds and 938/939 fixtures are reported; the failing fixture imports the
deleted file. That is useful compatibility evidence, but not a passing full
suite or proof of every diagnostic. Bootstrap refresh, stage equality, unit
suites, documentation, and final validation remain undone. Complete the
existing validation workflow on the finished current-dev tree; preserve
linked-meta edit fallback, captures and source locations in remaining users.

**S03 follow-up:** the retained linked-meta file has **ten**, not eleven,
smaller error-catalogue sections totaling 1,263 lines including headings and
blank lines. Their dynamic selection contracts and public consumers differ;
measure and review them before extending the migration. They may explain
some remaining cost, but line counts do not prove they explain most of the
5.5-second build gap to the older base, which includes other integration work.

Owners remain the diagnostic definitions/callers, linked-meta generation,
and ordinary macro/literal binding. No general import cache is justified:
meta imports deliberately reparse for each pass's symbols and emission
position. Keep import-only/one-report/many-report, native compile and startup
measurements distinct, and do not double-count capture samples within parsing.

### F33. P2 - Include the native backend in the optional build-cost score

**D06; Measured D.** On the configured macOS toolchain, time's hardware
counters cover the cc driver but miss its clang-cc1 child. Driver instructions
stayed near 109 million while directly measured backend work grew from
4.83 to 94.98 billion. Child-inclusive CPU time sees the backend.

Owner: `tools/build-scaling.py`. Measure the real backend or use an appropriate
child-inclusive measure, then recalibrate before accepting build-cost claims.
Distinguish authored/generated denominator growth. Preserve the optional
benchmark; this is a measurement correction, not itself a compiler speedup.

### F34. P2 - Avoid unused fixed-arity Lisp call environments

**D01; Measured D.** 1,000 warmed evaluator identity calls create 6,000
allocations: 5,000 for unused Maps and 1,000 for necessary argument arrays,
plus 1,000 Scope lifetimes. Positional values already own fixed-arity bindings.
Owner: `lib/lisp.x` `_run_frame`. Skip unused Map/Scope setup where producers
and consumers prove it unnecessary. Preserve rest/source-function frames,
closures, void, duplicate parameters, tail calls, and native reentry. Compare
allocation counts and evaluator/meta workloads using existing tests.

### F35. P2 - Skip impossible captures for top-level Lisp lambdas

**D02; Measured D.** With env NULL, every lexical lookup fails, yet lambda
creation walks free names and creates an empty capture Map. A 100-definition,
1,001-name probe requested 1.67 MB and retained 500 empty-Map allocations plus
100 real lambdas. Owner: `lib/lisp.x` `_make_lambda`. Skip impossible capture
work; retain nested captures and source lifetime. Compare allocations and
translation/evaluation alongside F34; these are retained objects, not a leak.

### F36. P2 - Decode Atom bytes and classify Match binders once

**D04; Measured D.** 1,000 Atom.first calls perform 1,000 pool lookups;
1,000 five-atom capture-layout analyses perform 21,000 warmed spelling lookups.
Owners: `lib/atom.x`, `lib/match.x`, existing `Symbol.first`. Decode directly
and reuse one classification without a new cache. Preserve compact/long/empty
names, identifier rules, quoted forms, and malformed diagnostics. Measure
cold preparation separately from cache hits; these are lookups, not claims
of that many new String allocations.

### F37. P2 - Make unzip compaction proportional to the remaining backlog

**D03; Measured D.** Compacting every 256 consumed entries repeatedly copies
the remaining tail: 10k/20k/40k lagged items move about 1.52/6.17/24.84 MB.
Owner: `lib/iter.x` `_unzip_compact`. Require the consumed prefix to reach both
the minimum and remaining tail, giving amortized linear copying. Check uneven
consumers, order, errors, and drain behavior. Tradeoff: more stale slots can
remain, bounded by backlog; current capacity does not shrink either. A new
ring-buffer subsystem is not justified by this bounded fix.

### F38. P2 - Reuse the visible-symbol snapshot owner

**D07; source-derived counts.** `Sym.unit_symbols` merges current file scope
after already copying it among base scopes; protocol inventory duplicates the
construction. Owners: `src/symbols.x`, `src/protocol.x`. Merge current only
when it is above the bases and call the existing owner. Preserve overlays,
shadowing, imports, and lazy inventory behavior. Count one removed G-row
update pass at file scope; do not remove the needed local-scope merge.

### F39. P3 - Stop recounting the meta-stub signature List

**D08; source-derived counts.** `_stub_arguments` in `src/meta-native.x`
repeats linear List.len in its loop condition: n(n+1) visits, 72 for eight
arguments and 4,160 for 64. Count once or walk once. Preserve argument order,
zero/large signatures, and linked/dynamic call parity. This is a small direct
cleanup; ordinary short signatures limit the likely overall speedup.

### F40. P2, investigate - Prove the middle Unit-macro snapshot's obligation

**D09; source-derived counts, removal unproven.** A tried Unit invocation can
take three semantic snapshots: 19 Map copies and nine merges before body work
(22/12 with local macro Maps). Owners: `src/compiler.x`, `src/macros.x`,
existing SymTxn. Trace whether the middle boundary independently serves
tolerant collection, rollback, borrowed-map identity, retained bundles,
counters, or editor facts. Remove only proven duplicate work. Counts alone
justify neither deleting transactions nor introducing a journal framework.

### F41. P2 - Preserve interpolation holes in named macro literals

**S02; independently reproduced on `1b71a410` and merged `2c8ddfb3`.** A named
Statement macro containing `%("path: ${$x}")` can cache the bare interpolated
string as a constant and emit invalid C such as `String_var(segments ...)`.
The spike wraps 50 strings as `%(${%"path: ${$x}"})` to build. Those wrappers
are evidence of a compiler gap, not the intended catalogue source style.

The same gap affects named Expression macros and nested Lists. Explicit
insertion, ordinary bound-variable interpolation, truly constant List strings,
and named String expressions outside Lists pass the focused controls.
The [probe record](../.context/deep-review/spike-reconcile-language/README.md)
preserves eight source cases and their sixteen outcomes across the two compilers.

Owner: `src/literals.x` `_cache_if_stable` recognizes bound identifiers but
misses unresolved macro holes; `src/compiler.x` can then cache the entire List.
`src/macros.x` defers runtime literals in anonymous bodies, masking this in
the old table rows. Keep deferred syntax visible through ordinary substitution
and lowering before cache admission; reuse existing unresolved-expression
facts where appropriate. Do not disable caching for all named macros.
Preserve dynamic values, repeated invocation with
different arguments, nested Lists, literal caching for actual constants,
evaluation order and canonical syntax constructed by Lisp. F15 has a related
constructed-string addition path, but neither reproduction substitutes for
the other. Fix this before adopting F32 so the catalogue rows move unchanged.

## Expected metric effects of the main waste revisions

These describe the intended replacement, not demonstrated gains. Total LOC
includes generated code when a row names it; beauty means fewer independent
owners and more direct expression of the same behavior.

| Scopes | Runtime | Compiler build time | LOC / source clarity | Principal limit |
| --- | --- | --- | --- | --- |
| F05 constant patterns | Less repeated preparation | Fewer temporaries may help | Simpler constant path | Must retain dynamic ordering |
| F06-F07 linear traversal | User runtime normally unchanged | Removes quadratic translation | Prefer one traversal; size not known | Depth and cleanup semantics |
| F32 catalogue | Prototype startup improves; application runtime unmeasured | Recorded stage-1 build about 38% lower | -156 authored, -1,940 generated lines; ordinary macros replace dispatch | F41 workaround, two duplicated rows, current-dev validation remains |
| F34-F35 Lisp | Fewer allocations and capture walks | Meta evaluation may improve | Less empty-state machinery | Some call frames remain necessary |
| F36 Atom/Match | Fewer lookups during preparation | Cold compiler patterns may improve | Reuse decoder/classifier | Hits often skip preparation |
| F37 unzip | Linear copying | Normally unchanged | Small extra condition | Bounded greater stale-slot retention |
| F38-F39 compiler repetitions | Compiler only | Less repeated work | Smaller/direct shared operations | Likely small end-to-end impact |
| F23 docs, F29/F31 cleanup | Little/no user-runtime effect | Less workflow/compile noise | Consolidation/deletion | Preserve public and tooling contracts |
| F33/F40 | No improvement established | Measurement/investigation first | No framework justified | Do not count proposed savings as delivered |

## Completed repairs

| ID | Repair | Delivered evidence | What remains separate |
| --- | --- | --- | --- |
| C01 | Runtime statics inside statement expressions | `4258f293`, integrated `1b71a410`; X09 probe also passes on `2c8ddfb3`, printing `3 3`, `1 1`, `2 2` | F01 unfinished initializer exits; F02 other type/value cases |
| C02 | Builds preserve configured Git hooks | `47e13cc1`, integrated `1b71a410`; configure matrix and combined gate passed | F22 absolute shared-hook admission |
| C03 | Construct the report table once | PR #98 head `8f95ec33`, merge `fcfaff40`, generated tree `2c8ddfb3`; all 254 rows preserved | F32 parsing/representation; F08 forward dependency reuse; F20 lint visibility |

C03's independent counts were parse: 53 -> 1 table builds, transform: 20 -> 1,
and a zero-expansion type unit: 0 -> 1. It removes repeated insertion but adds
one eager construction in unused cases. Authored production grew 20 lines and
the regression fixture 34; generated linked-meta C grew one line. This is a
specific useful tradeoff, not a measured improvement in all four metrics.

## Source-to-fix crosswalk

Every external finding is retained here even when it is closed, grouped,
pre-existing, or not yet strong enough to justify implementation.

| External numbered findings | Integrated scopes |
| --- | --- |
| X01 | F32, C03 (construction only) |
| X02 | F05 |
| X03 | F06 |
| X04 | F07 |
| X05 | F09 |
| X06 | F14 |
| X07 | F13 |
| X08 | F01 |
| X09 | C01 |
| X10, X11, X12 | F02 |
| X13 | F12 |
| X14, X15, X16 | F04 |
| X17, X18 | F10 |
| X19, X20, X21, X22 | F11 |
| X23 | F19 |
| X24 | F20 |
| X25 | F21 |
| X26 | F22 |
| X27 | F23 |
| X28 | F24 |
| X29 | F25 |
| X30 | F27 |
| X31 | F28 |
| X32 | F29 |
| X33 | F13 (test), F27 (plan) |
| X34 | F30 |
| X35 | F31 |

| External pre-existing findings, in source order | Integrated scopes |
| --- | --- |
| B01 match string lowering | F03 |
| B02 Name capture | F10 |
| B03 local reference | F17 |
| B04 forward linked-meta callee | F08 |
| B05 constructed string addition | F15 |
| B06 REPL reference receiver | F12 |
| B07 lint missing file | F21 |
| B08 Func macro hole | F16 |
| B09 aggregate const | F17 |
| B10 struct_ namespace | F11 |
| B11 warning in begin | F18 |
| B12 shared-cause table | F27 |
| B13 stale-lock race | F26 |

| This workspace's deeper review | Integrated scopes |
| --- | --- |
| D01 fixed-arity Lisp frame | F34 |
| D02 empty top-level capture | F35 |
| D03 unzip copying | F37 |
| D04 Atom/Match spelling | F36 |
| D05 catalogue | C03, F32 |
| D06 backend score | F33 |
| D07 symbol snapshot | F38 |
| D08 stub List.len | F39 |
| D09 nested Unit transactions | F40 |
| Earlier static / hook correctness repairs | C01 / C02 |

| Named-macro spike findings | Integrated scopes |
| --- | --- |
| S01 compiler catalogue replacement and measured results | F32 |
| S02 bare interpolated string in named Statement macro | F41, coordinated with F15 |
| S03 remaining smaller catalogues and residual-cost hypothesis | F32 follow-up; F28 contracts remain separate |

## Execution boundaries and coverage

Implementation is active. Sol workers own independent runtime, command/tooling,
and compiler changes in isolated worktrees. Keep a single writer for overlapping
compiler owners: F01/F07 cleanup; F03-F06/F15/F41 literal normalization; F09/F10/F16
macro binding; F11/F17 method identity/qualifiers. F41 precedes F32 adoption.
F08 remains a separate linked-meta correctness repair; removing the compiler
catalogue must neither claim to fix it nor weaken dependency behavior in the
remaining linked definitions. F13/F29/F34-F39 provide bounded
runtime/compiler cleanup work that does not require a catalogue redesign.

Initial assignments are F41 literal cache admission, F01/F07 initializer
cleanup and traversal, and F08/F39 linked-meta correctness and argument traversal.
F32 follows the F41 capability. Runtime, tooling, macro/type correctness,
documentation and the bounded investigations follow in owner-compatible
batches. This is an ordering of all 41 scopes, not a reduction in scope.
Progress and private handoffs live in `.context/post-integration-campaign/`;
landed results and any explicit deferrals are recorded here as batches finish.

Reuse existing suites and the focused cases above. First reproduce imported
claims on the implementation baseline. For performance proposals and claimed
gains, compare appropriate operation counts or timings, including known
retention/LOC tradeoffs; ordinary correctness fixes need their relevant checks.
The last implementation step is to review and fix the completed authored diff
before the existing publication validation and delivery workflow. This list
adds no recurring gate, benchmark requirement, or publication step.

Earlier broad checks passed on their recorded trees, including bootstrap
equality, units/fixtures, command/doc checks, executable examples, and cached
package checks. Those are compatibility evidence, not proof the defects above
are absent. This reconciliation did not rerun a broad gate, a full runtime
benchmark set, O2/sanitizer statement-expression probes, all package/host
variants, or an equally deep audit of threading, I/O, every compiler pass,
and graph lifetime/target logic. This session did not implement or benchmark
a replacement; the independently authored catalogue spike and its incomplete
validation are explicitly incorporated above.

## Design review

The proposed scopes favor canonical ASTs, actual binding identities, existing
cleanup/reference/conversion owners, and deletion of work whose inputs already
prove it unnecessary. They do not add origin authentication, a second semantic
validator, or generic caching/transaction machinery merely to unify appearances.
The JobLaunch rename is authorized. Local-reference semantics, Name binding,
REPL support, and catalogue arity retain explicit decisions rather than an
invented answer.
The spike favors ordinary named macros over a new catalogue caching mechanism:
it removes dispatch and serialized definitions with measured build gains.
Its source-workaround bug, duplicate rows, and untested runtime/validation
boundaries remain acceptance work rather than an assertion of four-metric parity.

Do not revive disproven shortcuts: blanket `_meta_apply` -> Lisp.apply breaks
legal same-session macro rebinding; subject rows preserve distinct identity/
spelling consumers; region fixpoints, cleanup ancestry, canonical List hits,
Map export rehash, and Match lifetime admission have demonstrated obligations.
F07/F40 target specific repeated work while preserving those obligations.
