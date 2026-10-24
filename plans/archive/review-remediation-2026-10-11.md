# Repository review and language-reference remediation

> Status: retired, 2026-10-24.
> Delivered work and earlier decisions are retained as historical evidence.
> The remaining scope has a separate active plan.

## Current owner

Continue from the [active plan](../review-remediation-2026-10-11.md). The text below retains its dated observations and earlier
decisions; it is not an additional implementation queue.

## Historical record

The following status was recorded before this closeout:

> Historical status: active - remaining decisions recorded on 2026-10-12.
> Repair batches A-E and acquired-value cleanup are delivered. The numeric,
> match, Var-to-String, and module decisions in section G are delivered
> through `3db5216c` and `c397213b`; the
> [repository review](repository-review-2026-10-12.md#decisions-recorded-2026-10-12)
> decided them later and governs where its text differs. The writing items
> remain open. Earlier checkpoints are history.

## Result

Repair demonstrated wrong behavior and checks that falsely report success.
Bring the existing book, syntax data, API comments, and continuation plans into
agreement with the intended language. Preserve the compiler's shared binding,
typing, placement, cleanup, and emission owners.

The supplied review is useful evidence, but it is not a ready implementation
specification. Its ranked findings mix defects, intentional semantics,
coverage limitations, and new policy proposals. The language study contains
181 gap rows, not approximately 150. Its draft grammar describes some bugs as
syntax, and several summaries contradict current behavior or its own later
verification evidence.

This plan does not adopt the study's draft EBNF or its sixteen-chapter outline
as a replacement specification. Repair existing semantic owners first. A
navigation outline can then link those owners without duplicating them.

## Inputs, evidence, and limits

Inputs are `x2c-review-findings-6529e868.md`,
`x2c-lang-study-6529e868.md`, and their adjacent reviewer, verifier, update,
and probe reports supplied by Gary. Their appendix citations often describe
`1e90f378`; their conclusions were checked against the baseline above.

The initial checkout was clean and exactly matched fetched `origin/dev`.
`make build-safe` succeeded and produced `builds/0/x2c`. Three independent
reviewers divided compiler findings, core language, and meta/runtime material.
The coordinating reviewer inspected the findings and their semantic owners,
replayed consequential probes, and independently tested tooling claims.

The companion ledgers account for the ranked findings, lower-value claims,
181 specification rows, and 35 original questions. Evidence labels distinguish
executed behavior, source inspection, known limitations, and open hypotheses.
An unexecuted inference is not an accepted compiler defect.

- [Finding evidence and reproductions](../reference/review-remediation-evidence-2026-10-11.md).
- [Language gaps and question dispositions](../reference/review-remediation-language-ledger-2026-10-11.md).

Local transcripts and probes are retained under `.context/critical-review/`;
full build, warning, raw-symbol, and documentation-mutation logs are under
`debug/critical-*`. Mutation checks used disposable source copies. Production
source and existing documentation were not edited for this assessment.

This was a review of the supplied analysis, not a fresh proof of the entire
repository. No full correctness gate, release test, performance campaign,
cross-platform run, or exhaustive protocol conformance study was performed.
Passing focused probes does not establish those broader properties.

## Upstream changes during this review

The final fetch advanced `origin/dev` by nine commits to `9004c40b`. The
coordinator inspected the complete authored delta and built that revision in
an isolated physical copy with `make build-safe`.

- `eff08cee` fixes reference-captured for-initializer cells. Its executable
  fixture passes with output `2`, `12 99`, `4 5`. Preserve this repair;
  it is no longer implementation work in batch A.
- `28fc8c97` fixes the module comment prefilter. Its trivia fixture prints 42,
  and the formerly failing commented opener now works. It also suppresses
  module discovery in recognized unreachable conditional arms. `#if 0` with
  a missing member succeeds; a local macro defined as zero still produces
  a member-read error because this is not full native preprocessing.
- That commit also excludes actual module members from script helper units.
  The installed payload and linked-meta adoption questions remain separate.
- Datum string validation and gate-worker interruption handling changed too.
  The datum reader repair does not repair compiler percent strings. Fresh
  current-tip probes still reproduce escaped-dollar loss, wrong match/catch
  binding, and signed percent-literal mismatch.

The ledgers retain original-baseline evidence and label these supersessions.
Unaffected source owners were compared across the delta; the full baseline
probe collection and broad gates were not repeated at the final tip.
Implementation should start from that final tip or recheck later changes.

## Corrections to the supplied analysis

- Unary `-` on a `Var` reaches its protocol member and works. A later rejecting
  dynamic fallback does not prove that all unary negation is rejected.
- Match binders do receive an identity from `Sym.define`. They bypass ordinary
  declaration facts and template-local handling, and lowering loses that
  identity. The report's literal claim of no binding identity is inaccurate.
- Typed List bracket reads work through inherited List access. Correct the
  contradictory rejection sentence; do not implement another access path.
- Eight native Lisp arguments is a stack-allocation threshold, not an arity
  limit. A nine-argument native call works.
- A trailing `kernel` field is not accepted as an ordinary constructed source
  function. The unmarked control is accepted. Public canonical syntax and
  internal bound/lowered forms are different contracts.
- `MatchRow` is a hole category, not a supported decorator target. Adding it
  to the target table would introduce a feature, not repair documentation.
- `x2c_place` and Lisp `x2c.place` are documented context-specific spellings.
  No canonical-spelling migration is needed.
- Script failure is not invariably status 1: `cmd-fail` preserves its child's
  status. Shell status 134 is not a portable language definition of abort.
- A C/H-only fixture proves its declared emission phase. Such fixtures are not
  inherently broken because they do not also compile. The lvalue fixture is
  broken because its expected output violates its claimed operation.
- Optional examples, syntax checks, and proofs are deliberate policy. Their
  absence from a gate is not, by itself, a process defect.
- Unused public API and unreferenced local branches are not automatically
  deletable. External callers and recoverable work must be considered.

The study also misses a current contradiction: `lib/meta.x` still says function
rules receive lifted lambdas, while the current guide and implementation
exclude compiler-written definitions from program function rules.

## Remediation order and dependencies

| Batch | Result | Dependencies | Readiness |
| --- | --- | --- | --- |
| A | Correct match/catch binding identity and macro hygiene | Preserve landed loop-cell repair | Implement remaining paths after scoped design review below |
| B | Remove undefined local reads, invalid dynamic stores, and wrong acquired-value cleanup | Standing acquired-value requirement | Implement demonstrated paths; do not invent emitter validation |
| C | Correct literal decoding and sizeof operands; settle wide indexing | Existing C operand contract; literal/escape contracts; index decision | Literal/sizeof repairs scoped; escape contract and index choices explicit |
| D | Make existing build and verification commands report failure truthfully | None | Existing-check repairs ready; broader gates remain proposals |
| E | Repair module splicing boundaries and optional proof classification | Existing textual-splice contract | Narrow repairs ready; self-host adoption separately bounded |
| F | Reconcile book, generated API text, grammar, and continuation status | Confirmed source/probe evidence; semantic decisions below | Most wording work ready; unresolved claims stay explicit |
| G | Specify rewrite visibility, numeric equality, evaluation order, and support boundaries | Decisions below | Do not implement competing semantics before decision |

A, B, D, and the bounded parts of E can proceed independently in isolated
implementation worktrees. A owns shared binder/hygiene edits; do not split
those among simultaneous writers. F may proceed for settled facts, but grammar
and normative text must follow any accepted changes from C and G.

### A. Preserve lexical identity through match, catch, and closures

**Problem.** Match binders receive stable identities through `define`, but
bypass the declaration facts that ordinary locals and catch binders receive.
Closure capture consults automatic-binding facts. A lambda can resolve a same-named global
instead of its enclosing match binder. Separately, match and catch declarations
inside a macro can capture a caller expression's same-named local. The separate
`for` initializer cell defect was repaired upstream during this review.

**Owners.** `Compiler.define_match_binders` and catch binding in
`src/compiler.x`; ordinary declarations in `src/symbols.x` and `src/parse.x`;
template binding in `src/macros.x`; capture resolution in `src/lambdas.x`;
cell placement and lowering in `src/component-lambdas.x` and
`src/component-match.x`. `MatchCaptureLayout` already owns capture order.

**Implementation.** Route match locals through ordinary declaration handling
and carry their identities to component declarations. Preserve the
distinction between pattern capture tokens and lexical bindings. Make the
template's pattern declarations participate in the same private-binding
substitution as ordinary macro locals. Caller argument bindings remain their
original bindings. Preserve upstream's loop-initializer cell placement and its
ordinary block scope; do not add another lambda-specific lookup or spelling
replacement.

**Acceptance.** Match-arm value and reference captures read/write the arm's
binding while a same-named global stays unchanged. A caller local remains 77
inside a macro whose pattern binder is 5, for both match and catch, including
guards. Nested scopes and repeated binder spellings retain separate identities.
Retain the landed for-initializer fixture as a regression boundary. Compare
source and constructed/template routes for the remaining repairs. Preserve the
existing capture lifetime and loop-binding contract; do not change to fresh
per-iteration cells merely to eliminate a crash.

### B. Remove undefined reads and preserve writable-lvalue requirements

**Uninitialized capture.** `_forwarded_hole` in `src/macros.x` reads `direct`
after neither match arm assigned it. Initialize the absent result to `void`,
or return from each matching arm and decline otherwise. Keep one absence
representation and the current capture projection owner. Prove the ordinary
nonmatching capture path, not only the successful forwarded-hole path.

Clang's warnings also identify `name`/`mods` in
`Emitter._static_binding`. The emitter consumes an established binding shape.
Do not add a second malformed-AST validator or default values merely to quiet
that warning. Trace the producer guarantee and express the exhaustive shape
directly if a warning-clean restructuring is needed. No reachable wrong-input
path has been established for that second site.

**Dynamic native stores.** The current lvalue fixture takes the address of a
`register` object and writes through a discarded `const` qualifier. Dynamic
lowering must preserve the writable/addressable requirements it bypasses.
Inspect ordinary expression addressability and declaration storage facts;
reuse or complete that owner once, then consume its result in dynamic update
lowering. The current addressability helper alone is not sufficient: it checks
expression shape and lambda snapshots, not all native storage restrictions.

Keep valid volatile updates. Reject an unsupported non-addressable target at
the semantic boundary, or preserve a valid native operation if the existing
owner already provides one. Do not remove native `register` support globally.
Split the existing mixed fixture into positive writable targets and focused
negative const/register cases so valid cases still reach native compilation.

**Acceptance.** Nonmatching forwarded captures translate with both normal and
focused unoptimized builds. The initialized form has no uninitialized-read
warning. Dynamic update of valid scalar/Var/volatile lvalues works; const
targets cannot silently accept a write; unsupported register addressing gives
a deliberate diagnostic. Existing enum and bitfield behavior stays intact.

**Acquired-value cleanup.** `$auto` currently schedules cleanup of the user
binding, so reassignment changes which value is cleaned. Retain the acquired
value once through existing binding, placement, Cleanup, and region operations.
The public initializer still returns that value. Acceptance proves single
evaluation, cleanup of the acquired value after reassignment, and existing
normal/error-transfer cleanup behavior. This follows the standing requirement;
current fixture behavior must not override it.

**Empty parameter forwarders.** Alias constructor forwarders still produce
`Values_new()` despite the generated-prototype change. Reuse the canonical
`void` parameter representation in `Compiler._forwarder`. Check generated
declarations/definitions and compile the focused output with strict-prototype
warnings. This repair does not depend on adding a recurring warning flag.

### C. Repair literal and sizeof parsing; settle wide indexing separately

`Type.numeric_literal` receives signed percent-literal tokens, but its
magnitude helper expects unsigned digits. `%(-5)` acquires the wrong family,
and larger negative spellings can be rejected. Handle the optional sign at the
shared numeric-token boundary before magnitude selection and value decoding.
Do not repair only match labels or add a second percent-list numeric parser.
Preserve suffix/radix behavior and distinguish a signed data token from C's
separate unary-minus expression. Select signed-minimum types using magnitude
without overflowing a signed intermediate.

Acceptance covers positive/negative decimal, supported radix forms and
suffixes, signed minimum values, overflow, runtime versus inserted values,
and matching a runtime negative against its percent-list pattern. Do not fix
the symptom by making all Var numeric families compare equal.

Percent-string decoding has a separate reproduced problem: `_decode_segment`
unescapes first and then replaces `$$`, so two escaped dollars collapse into
one. State the escape contract from the reference and scripting guide, then
decode once without losing which dollar was escaped. Reuse the literal owner;
do not repair only the generated syntax inventory. Cover escaped dollars,
double-dollar escapes, interpolation adjacency, literal backslashes, and
ordinary strings. Refresh generated lexical data only after that behavior is
settled and verified.

`sizeof (xs)[0]` is valid native C and measures one array element. x2c rejects
it because `_parse_sizeof` consumes the parenthesized expression and returns
before its postfix continuation. Restore the ordinary unevaluated unary-operand
grammar through the existing expression parser, keeping the type-name branch
distinct. Do not add a second postfix parser. Acceptance distinguishes
`sizeof xs`, `sizeof (xs)`, `sizeof (xs)[0]`, and `sizeof(type)`, and verifies
that a side-effecting ordinary operand is not evaluated. Preserve existing
native VLA obligations rather than promising that every sizeof operand is
unevaluated in all native cases.

Wide native indices currently narrow at int-taking collection APIs. The
demonstrated `4294967297L` write changes element 1. Direct C-like calls to an
int parameter ordinarily permit conversion; that is different from a library
promise to reject an out-of-range index. Before changing APIs, decide whether
bracket syntax promises range-preserving conversion. Recommended behavior is
that an index outside the representable domain cannot alias a valid element.
Superseded 2026-10-12 by decision 2 of
[the repository review](repository-review-2026-10-12.md#decisions-recorded-2026-10-12):
indices stay 32-bit `int`, and the book states it.

For that decision, inventory String/List/Array reads, writes, compound writes,
and slices, including Var-index dispatch and direct methods. Reuse the existing
index/slice normalization and conversion owners. Choose one checked conversion
boundary or one compatible wider API design; do not scatter casts or checks
among component templates. Document any direct-method versus bracket difference
explicitly. Changing public signatures requires a compatibility assessment.

### D. Repair existing checks before expanding verification policy

1. Replace the five `status && grep` assertions with explicit failure paths.
   Do not rely on `set -e` for compound lists. The host's Bash 3.2 also ignores
   failing bare `[[ ... ]]` under `set -e`; repair assertion failure behavior
   across the affected probes or enforce the already-required shell version
   at their existing entry boundary. Do not silently skip assertions.
2. Capture translation status before filtering region warnings. Capture each
   graph AST producer's status before normalization and comparison. A crashed
   producer must not pass because text is equal or empty.
3. Make assertion-dependent Python probes remain effective with optimization,
   using explicit failures or a clear existing-entry check. This is a test
   correctness repair, not a new verification stage.
4. Compare generated documentation bytes for equality; use a line diff only
   to display a mismatch. Reject missing section delimiters before inspecting
   the existing contract-ledger section.
5. Repair Make path handling and mode-file lookup together. At minimum reject
   unsupported checkout paths with nonzero status before work begins; a command
   that produces no stage compiler must not report success. Full arbitrary-path
   support needs a separate measured scope if more than quoting these owners
   is required. Do not claim support after repairing only `basename`.
6. Match the known `stage-diff-0` failure in both Make 3.81 and Make 4 formats,
   without treating an arbitrary build failure as permission for a second
   bootstrap round. Preserve fail-closed publication behavior.
7. Remove the undeclared stale `meta-helper-compiler-query.compile-status`
   sidecar after confirming that fixture's current declared phases. Keep
   emission-only fixtures when emission is their intended contract.

Fault injection must show that a wrong status, crash after warning, failed AST
producer, missing heading, newline drift, and unsupported build path fail their
existing commands. Ordinary passing inputs must still pass.

**Separate policy proposals.** `doc-check` currently accepts a wrong expected
sample output after generated text is refreshed; `doc-outputs` rejects it.
This is a real coverage boundary. Adding `doc-outputs` to every documentation
gate, adding strict warning flags, or compiling every C/H-only fixture expands
recurring work. None is silently approved here. First measure changed-page
sample checking or relocating/consolidating existing work, identify comparable
cost to remove, then ask Gary to select the policy. Keep optional syntax and
raw-symbol checks optional. Do not add a second gate framework.

### E. Complete module boundaries without redesigning modules

`module` blocks are ordered textual splices into one translation unit. Members
do not become independent compilation units or acquire their own namespaces.

- Preserve the landed conservative candidate test and existing lexical owner.
  Commented module openers now work. Preserve the shared conditional-arm
  classification added upstream; do not rebuild either mechanism.
- Avoid pointer arithmetic on the null representation of empty source text
  in `Splice.own`. An empty member is valid input. Handle the empty range
  before pointer arithmetic rather than banning empty members.
- Update the optional raw-symbol proof's classification for intentionally
  unsupported module units. Preserve one receipt per input and ensure ordinary
  sources containing `module` identifiers/comments are not broadly excluded.
  Prefer existing classification knowledge or the focused module fixture set
  over a second incomplete parser in shell.
- Compile/link the included-module fixture's consumer and provider as focused
  acceptance evidence, proving the member's public declaration reaches the
  header. A textual C comparison alone does not prove that contract. Adding
  recurring native phases needs the same cost/approval decision as D's broader
  fixture proposal; this plan does not silently expand that requirement.
- Document entry syntax mode, ordered duplicate splicing, and preprocessing
  order as properties of textual assembly. Recognized unreachable arms now
  suppress member reads; unresolved native conditions still permit eager reads.
  Do not add duplicate-member validation solely for earlier diagnostics.
- Before splitting shipped `lib/` or `src/` units, extend payload copying and
  linked-meta discovery to the declared member closure. Preserve relative
  member paths; do not scan all nested files as independent units. This is an
  adoption prerequisite, not a present install failure: no shipped source
  currently uses module blocks.

**Package entry agreement.** A fresh local `.xp` source package installs
successfully, but importing that installed package reports unknown package
because `SourceView.package_entry` searches only `.x`. Align source-entry recognition
between install and import. The recommended repair supports the `.xp` entry
already accepted by installation, preserving existing `.x` precedence and
package ownership. Verify installed import and a same-name entry precedence
case. If `.xp` packages are intentionally unsupported, installation must reject
them explicitly instead; do not leave a successful unusable installation.

Acceptance includes comments/trivia, empty members, nesting, member diagnostics,
included public declarations, missing files, conditional blocks, and unchanged
non-module output. Module adoption additionally needs an installed-home probe
with a member-defined meta function. Use `module_source` and its dependency
information rather than inventing another ownership graph.

### F. Repair the existing book and syntax owners

Work from the companion row ledgers. A documentation gap is resolved either by
correcting its owner, linking an existing contract, recording an implementation
limit, or explicitly retaining a semantic decision. It is not resolved by
copying the observed implementation into normative prose.

**First corrections.** Remove stale `@` operator and `Slice` claims. Correct
Var negation, typed List access, descriptor capacity, fresh meta collection
insertion, project compiler queries, meta compiler selection, supported macro
categories, and function-rule visibility. Correct API comments before
regenerating library pages. Qualify cleanup at selected Error transfers versus
the fatal floor, detached-scope finalization, and script status propagation.

Correct two protocol-guide contradictions: static protocol bodies are private
and supported; declarations retain AST nodes but create no runtime object.
Keep the existing protocol collection and adoption design. The supporting
fixtures and fresh associated-type probes do not establish exhaustive protocol
conformance, so do not use them to close unrelated protocol questions.

Separate parse acceptance from completed language support. `goto;` is rejected
by emission, `sizeof (xs)[0]` is rejected by parsing, and a translated comma
case label still needs native constant-expression validity. Keyword method names
work, but that does not make every keyword usable as a native C variable.
Document that native `exit` and `longjmp` bypass lexical deferred cleanup;
do not add foreign-call interception as a documentation repair.

**Syntax.** Edit `etc/syntax/grammar.x`, `lexical.x`, and `extensions.x` where
they are the generator inputs; regenerate through `tools/syntax-spec`. Update
contextual prose in the existing syntax pages. Add module blocks and the
verified S-row corrections. Do not hand-edit generated EBNF. Keep the grammar
descriptive: it is not a second parser or an AST validator. Existing focused
fixtures and optional syntax checks supply evidence for affected productions.

Correct the study's module grammar before using it: nesting a module inside
`extern "C" { ... }` is not supported simply because its `unit-item`
nonterminal includes module blocks. The old comment rejection was a fast-path bug, now repaired upstream,
not a normative lexical constraint. The grammar also needs explicit contextual
boundaries for scripts, decorators, macro categories, typedef names, and
constructed syntax. An unexecuted EBNF cannot certify parser conformance.

The production-family review found additional overacceptance: missing static
typedef termination, shared definition/invocation names, scalar sequence calls,
percent-braced `with` bodies, unparenthesized pointer selectors, and unrestricted
macro-body alternatives. Nine translation counterexamples were replayed; eight
reject and do/while without a semicolon translates. Correct the draft using the
existing recognizers before incorporating it into generated syntax data.

**Ownership of text.** Keep language contracts in the book, syntax forms in
the syntax reference, runtime API contracts in authoritative source comments
and generated library pages, and compiler implementation routes in internals.
Guides teach through examples and link complete tables. A reference may link
the protocols guide while it is the designated semantic owner; moving that
material is not required to fix a contradiction. Do not require a page for
every private runtime source file or a tour example for every feature.

**Continuation records.** Reconcile the foundation plan's opening status and
next-step instructions with its dated delivered log. Preserve genuinely open
work and historical holds. Archive the completed module-block plan with its
landing evidence and index it. Re-plan String switch through the current
component and placement APIs; the fixture is a prototype, not proof that the
ordinary feature ships. Keep its accepted behavior, including fallthrough,
break/continue, duplicate labels, aliases, and single selector evaluation.

Existing overlapping plans remain owners of their decisions. In particular,
the foundation plan owns rewrite/component continuation; String switch owns
that feature; the post-integration fix list already owns plan-status and
documentation-classification cleanup. Cross-link this evidence instead of
creating two competing implementation queues or declaring old work complete.

The String-switch plan specifically names removed `x2c_literal_int` and now
uses `add_support` for a compiler-written helper. That operation offers the
definition to program function rules; written definitions use `add_early`.
Refresh those interfaces within the accepted feature design. Also correct the
module plan/book's blanket prototype-before-use claim: a member's early
function can call a later entry function without a prototype. Complete-unit
function collection and private type emission order are different contracts.

Complete the reference with a compact catalog of public canonical source forms
and their positions, rewrite ordering/decline/visibility, and compile-time Lisp
truthiness, binding, host `set_global`, and actual implementation limits. Link
existing API owners. Do not publish every internal bound/lowered carrier as
source syntax or turn the eight-slot fast path into an arity limit.

### G. Decisions recorded on 2026-10-12

These decisions replace the earlier question list. The
[repository review decisions](repository-review-2026-10-12.md#decisions-recorded-2026-10-12)
of the same day supersede the index, match, and Var-to-String text below;
each subsection notes the delivered behavior.

#### Numeric comparisons

Use the C comparison rules for the corresponding native numeric operands.
Do not convert every number to double.

```x2c
Var a = 3;
Var b = 3L;
a == b;   // true: C compares int 3 and long 3 as equal
a === b;  // false: the value types differ
```

For value types, `===` requires equal values and the same type. Reference
objects retain identity comparison. Review hashing, Map keys, and sorting with
this change so their contracts remain consistent. Gary did not separately
approve a new Map key policy; an actual conflict needs a concrete example.

#### Collection indices and match

An index such as `4294967297L` must not narrow to index 1. Reads, writes,
and slices use the collection's existing out-of-range behavior. Put the
conversion in one owner; do not widen every public API automatically.

Superseded by repository review decision 2: indices are 32-bit `int`, the
book states it, and a wider value is outside the supported domain. No
compiler or runtime change was made.

Matching a non-List Var must reject the input. A genuine empty List remains
valid and can match an empty-List pattern. Update the guide's current unchecked
conversion wording when implementing the change.

Superseded by repository review decision 3, delivered in `2e8c1877`: a Var
subject whose tag is not `<list>` matches no List arm and reaches `default`.
The fixture `match-var-non-list` covers it.

#### Var to String

Implicit assignment invokes the input's `.str()` method:

```x2c
Var value = 42;
String text = value; // "42", through value.str()
```

Raise a runtime error when the input has no `.str()` method. Explicit
`value.string()` continues to extract an existing String payload. This decision
does not commission general class-unboxing checks.

Superseded by repository review decision 4 and batch 10, delivered in
`e2c9fa40` and `4b387196`. A String destination reads the Var's String
payload or its display text. Explicit `.string()` raises `<no-convert>` for
another tag, and so do `.list()`, `.map()`, and the other explicit readers.

#### Module follow-ups

Report the physical member file and its correct line and column when an
included module's compile-time effect is replayed. Commit `9db47909` fixes
entry-file columns and source context for code after a module block's closing
brace. Its fixture covers that separate case, not included-member effect replay.

The remaining replay path records the module entry filename in
`src/macros.x` and freezes token coordinates without the member filename in
`src/compiler.x`. Imported Lisp effects read the entry file and clear
`line_markers` before evaluation. The source review therefore retains this
follow-up; the related diagnostic repair does not close it.

The included-member failure was previously reproduced. Its executable
reproduction was not rerun during this source-only review at `2b5ee957`.
Before implementation, recheck that exact case on current dev, then repair its
source mapping through the existing owners. Preserve the delivered post-block
column behavior. This task does not commission a broader diagnostic redesign.

Normalize companion member paths before checking containment. Accept harmless
`..` segments that stay inside the companion directory. Reject paths that
escape it, including escapes through symlinks. Do not impose a spelling ban
as a substitute for checking the resolved destination.

#### Writing and supported features

Finish three explanations in the existing book:

1. Show canonical source forms and the positions where each form is legal.
2. Explain rewrite order, decline, and visibility with accepted examples.
3. Explain compile-time Lisp truthiness, binding, and host `set_global` limits.

Maintain a factual list of supported language features and platforms. Update
that list as support changes. This is ordinary documentation maintenance,
not a new ABI promise or portability campaign.

#### Settled boundaries and withdrawn questions

- Keep established evaluation order. Do not promise universal left-to-right
  evaluation; C function arguments remain unspecified. Developers can use
  explicit locals when order matters. Preserve collection and quotation promises.
- Preserve prototype chains and List/Type interoperability. Do not introduce
  blanket sibling typedef or scalar restrictions. `typedef List Type` remains
  a working example of the intended relationship.
- Offer practical CPP compatibility without a new CPP/module interaction
  guarantee or native conditional dependency redesign.
- Thread remains x2c's simplified thread abstraction. Sharing the word
  "thread" creates no interoperability obligation with arbitrary C threads.
- Withdraw the claimed u128 feature defect. The internal fallback dates to
  `4235c383`; a lookup entry does not emit a source typedef. No 128-bit feature,
  alias removal, or rejection change is commissioned by this discussion.
- Repair false passes in existing checks. Add no recurring gate or default lint.
- Acquired-value cleanup is already delivered; do not reopen it as lexical defer.

The [foundation plan](language-components-foundation.md#recorded-decisions)
owns rewrite visibility, template binding, and constructed `with`. The
[String switch plan](string-switch.md) owns that selected feature. The
[quotation plan](../quotation-adoption-audit-2026-10-03.md#remaining-work)
owns `_Alignof` and the scalar generator cleanup. Historical coverage ledgers
are evidence, not additional task queues.

## Validation and delivery for a later implementation

Use meaningful fail-before/pass-after evidence for each accepted defect.
Keep tests in existing suites and probes; do not add a recurring stage merely
because this review found an uncovered case. Source-only, native-compilation,
and runtime assertions prove different boundaries and must be named accurately.

Each coherent batch ends by reviewing and fixing the complete authored diff,
including generated changes. Then follow current root delivery instructions.
Direct code delivery uses `tools/gate-state.py ensure agent-pr-check` on the
final integrated tree; documentation-only delivery uses `doc-check`. A
shared-integrator submission follows its focused-evidence exception instead.
Performance-sensitive changes use the existing performance-checkpoint policy.
Do not run broad gate components repeatedly just to collect review evidence.

The subsequent implementation request authorizes confirmed repairs and normal
validated delivery to `dev`. Use the recorded decisions above. Keep uncommissioned proposals and expanded gates out.

## Design review

The plan repairs facts at their existing owners: lexical identities at binding,
numeric decoding at Type, bounds at conversion/normalization, splicing at source
assembly, status at command boundaries, and semantics in the book. It does not
add origin authentication, recursive AST validation, a replacement parser,
duplicate runtime checks, or a new gate framework.

The largest risks are silently changing public numeric equality, promising
evaluation order without complete lowering evidence, and treating internal AST
reachability as stable source syntax. Those changes remain decision-dependent.
Self-hosted module adoption and broader verification policy are separate from
the narrow bugs that motivated them. Completed implementation must be reviewed
against these boundaries before publication validation.


## Implementation checkpoint, 2026-10-11

The confirmed repairs below are implemented against `9004c40b`. This checkpoint
records focused evidence before the final integrated publication gate.
No recurring gate or validation order was expanded.
Delivery, recorded 2026-10-14: these repairs went directly to dev on
2026-10-11, ending at `cdd73a7a8`. This record has no gate result for that
publication. PR #193 (`4d4c7aa9d`, 2026-10-13) later recorded
`tools/gate-state.py ensure agent-pr-check` passing on `900640f7`, a tree
that contains these repairs. No separate delivery report or performance
report was produced.

| Scope | Implemented result and focused evidence |
| --- | --- |
| A: binding identity | Match and catch binders use ordinary declarations and existing template-local identity. Original global-shadow, caller-hygiene, and guard probes pass. The combined `match-binder-identity` fixture passes. Static matching keeps scalar capture temporaries; no capture array was added to that path. |
| B: local correctness | The forwarded-hole local starts at the existing absent-value sentinel. Empty alias constructors use `(void)`; the alias probe compiles with `-Werror=strict-prototypes`. Dynamic native writes reject const or non-addressable register targets through expression resolution. Valid volatile and register-pointer targets pass. |
| C: literals and sizeof | Signed percent tokens select their intended numeric family, including signed minima. Emission preserves decoded dollars and uses portable signed-minimum C spelling. `sizeof` reuses unary operand parsing, including postfix continuation. Focused positive and rejection fixtures pass. |
| D: existing checks | Existing shell assertions explicitly fail, producer status survives filtering, assertion-dependent Python entries reject optimization, generated bytes are compared directly, missing ledger delimiters fail, and invalid Make paths/stages fail. The stale fixture sidecar is removed. Both Make retry formats pass focused tests. Independent fault replays confirm the repaired failures. |
| E: source boundaries | Empty module members return before null pointer arithmetic. A targeted instrumented owner fails before and passes after. Installed `.xp` entries import successfully; source lookup retains `.x` precedence. Competing same-stem installation remains an output collision. Focused native proof, recorded 2026-10-13 at `5e469a1c`: in `unittest/compiler-fixtures`, `x2c build module-block-included.x module-block-included/shapes.x` links, and the program exits 12 (`2 * 2 * 3`), so the member's `square_area` and `struct Square` reach the consumer through the entry's header. The fixture's recurring phases stay `symbols c`. |
| F: settled descriptions | Book and source comments correct the verified contradictions. Existing syntax data and contextual contracts were corrected and regenerated. The completed module plan is archived; foundation and String-switch continuation records use current owners. `syntax-spec check` reports no stale outputs. |

### Repairs merged during planning, recorded 2026-10-12

These repairs are on dev and strengthen work already marked delivered. They
change no recorded semantic decision and complete no additional selected
backlog item. This update inspected source changes and checked-in fixture
expectations; it ran no build or executable reproduction.

| Delivered commit | Behavior and checked-in evidence | Plan impact |
| --- | --- | --- |
| `5a20cb8c` | Leading `$$` reaches the percent-string segment scanner. The `percent-dollar-escapes` fixture expects `%"$$"` to produce one literal dollar and also covers adjacent interpolation. | Extend batch C's delivered literal repair notes. The old leading-dollar limitation was removed from lexical documentation and syntax data. |
| `2557fd72` | Negative percent integer tokens without a `u` suffix select signed types in every radix. `%(-0x80000001)` retains -2147483649; `%(-1u)` retains unsigned modular negation. The `percent-signed-numbers` fixture covers wide values and matching, and the book explains the rule. | Extend batch C's signed literal coverage. Cross-type Var comparison remains separate decided work. |
| `e7b2be43` | Region analysis retains acquired cleanup when a nested assignment can leave the earlier managed value on another path. The `managed-acquired-regions` fixture expects return-escape warnings after conditional and loop reassignment. | Extend the delivered acquired-value cleanup notes below. No new ownership policy or general alias analysis is selected. |
| `9db47909` | Diagnostics for entry-file code after a module block use the file's original columns and context. The `module-block-same-line-diagnostic` fixture expects column 81 for its malformed code after `}`. | Record the delivered repair. Keep only included-member effect replay in the diagnostic follow-up above. Companion-path normalization remains separate work. |

### Acquired-value cleanup follow-up, 2026-10-12

The small `$auto` prototype saves the acquired value and passes its runtime
reassignment probe. It removes two existing `region-escapes` warnings, at the
returned Array and a returned closure that captures that Array. The region
pass attaches the deferred cleanup to a local fact; it does not retain shared
acquisition identity across the new saved local.

The prototype was excluded from the first delivery. Gary then approved a
separate design and its implementation. The acquired value is saved in a
hygienic const local, followed by ordinary deferred cleanup. The region pass
shares that stable value's cleanup independently of its allocation region;
reassignment detaches the public binding. Mutable defer targets retain their
existing binding-local analysis. Scope allocation attaches the handle's
cleanup to its existing storage region, without joining copied NULL slots.

The Lisp evaluator's lazy Scope and Map growth's replaceable staging buffers
use explicit late-bound defer. Existing Array and closure warnings remain
unchanged. Focused fixtures cover replacement values, conditional aliases,
Scope slot population, ownership moves, const and volatile locals, aggregate
snapshots, and lazy allocation. No general alias analysis or gate is added.
Delivery, recorded 2026-10-14: the acquired-cleanup commits `c4d52d5b6` and
`e7b2be431` went directly to dev on 2026-10-12, not through a PR. PR #193
later recorded an `agent-pr-check` pass on `900640f7`, a tree that contains
them. No separate delivery report or performance report was produced.

Wide indexing, cross-tag numeric equality, class unboxing checks, rewrite
visibility policy, additional platform guarantees, and expanded gates remained
outside this implementation. The repository review later decided the first
three; section G notes the delivered behavior. A full new language specification is still a
separate writing effort; the existing row ledger retains its open questions.
