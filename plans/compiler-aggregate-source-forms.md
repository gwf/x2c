> Status: active -- final dual-macro integration pending, 2026-09-29.
> Settled Array/Map adoption, sequence capture repair, Array sequence syntax,
> and constructed String repair landed on dev at `7699e277`. The earlier
> public Segment proposal was withdrawn; mixed String rows now use a shared
> canonical `source_string_content` projection without a new syntax role.
> Historical proposals and earlier gate results below describe their own trees.

# Aggregate source forms

## Final campaign overlay (publication pending)

Array and Map source macros own their complete outer forms; the repaired
sequence capture path admits the Array Expr sequence position. Map Entry
reconstruction retains its existing resolved key/value owner. Mixed String
text, expression, and cached rows share `source_string_content` between
literal production and expression resolution. This preserves the established
segment representation and avoids a public Segment parameter kind. Parser
primitives still create canonical AST, and all ordinary binding, conversion,
cache, and emission work stays in its existing owner.

This overlay is part of the [compiler dual-macro campaign](compiler-dual-macro-contract.md)
and its [architecture reference](compiler-dual-macro-architecture.md). The
historical Segment proposal and publication record below remain as evidence
of the earlier decision path. Final integrated-tree validation and delivery
are recorded in the campaign contract after publication.

## Result and scope

Give Array, Map, and String semantic recognition and reconstruction a shared
source-form owner. Keep ordinary resolution, binding, conversion, cache,
lifetime, and emission operations responsible for their existing semantics.
Repair the macro-case sequence capture defect that currently prevents the
natural Array adopter. Complete each family rather than declaring it covered
because its outer constructor changed.

A concrete Array adopter recognizes `%[$items...]`, resolves each member in
order, and rebuilds with the original root type and retained children. A Map
adopter does the equivalent for `%{${$rows...}}`, including computed Entry
rows and key/value resolution. A String adopter must carry mixed cached text,
`segvar`, `segexp`, and legal constructed `segraw` rows without changing
conversion or evaluation order.
The existing loops perform semantic work and may remain.

This plan extends the [dual-macro campaign](compiler-dual-macro-contract.md)
and its [architecture](compiler-dual-macro-architecture.md). Parser primitives
remain the owners that first manufacture canonical AST. There is no attempt to
make a literal parser invoke its own source macro. Constructed canonical Lists
remain legal regardless of their origin.

## Evidence and limits

| Evidence | Established result | Limit |
| --- | --- | --- |
| Local `2eb5f1d4` on `e1848c54` | Quoted Array accepts an Expr sequence hole; mixed and empty sequence fixture | Not shipped or refreshed on current dev |
| Local `a1cef5e0`, same tree as worker `9356cc12` | Array semantic recognition/rebuild and empty initializer use source macro; retained child and unresolved child probe | Uses direct `Macro.pattern`/`List.match` workaround |
| Worker focused verification | Five fixtures, native bound-template probe, stage 1, 192 C/H stage comparisons passed | Local seed used; shipped-bootstrap publication gate not run |
| Map native probe, rerun 2026-09-29 | Empty and two-row Map match/rebuild retain root type, row and key/value identities | No semantic Map adoption, computed rows, or typed conversion proof |
| Macro-case probe on old candidate | Structural match succeeds; case publishing returns incomplete route, destination -1 | Reconfirmed on current dev below |
| Current-dev native probe at `d537e8d8`, independently rerun | Expanded direct match succeeds; expanded case and pending case both fail; `(!and *items)` is malformed while `(*items)` has slot 0 | Reproduction uses existing current-dev compiler objects; repair has not been applied |

The previous conclusion that these families offered no adopter was too broad.
The Array adopter and Map probe contradict it. String needs its own segment
representation proof; the limitations of Expr sequence holes do not reject
String source forms in general.

## Ownership and publication coordination history

Confirmed with both pinned chats on 2026-09-29:

1. **Continue beautification Wave 4** owns Wave 5's `expressions`, `transform`,
   `protocol`, `emit`, `regions`, `cache`, `diagnostics`, and `format` files until
   it lands and explicitly releases them. It is the first publisher, using
   `tools/land-dev`, and sends the landing SHA to both other chats. `literals.x`
   is outside Wave 5, but aggregate checkpoints remain unpublished meanwhile.
2. **Execute dual-macro migration plan** has no active edits or upcoming
   publication. It releases `lib/meta.x`, `src/macros.x`, and
   `src/grammar.xmacro` to this batch and agrees not to publish competing work.
3. **x2c meta-language aggregate source forms** is the sole publisher for the
   subsequent aggregate batch. Fetch the announced landing SHA, replay the
   changes onto the released, beautified owners, and announce ready/base SHAs
   to both chats before final validation. Do not blindly cherry-pick old whole
   functions over their rewrites.
4. Reserve a quiet performance window with both chats. If dev advances, fetch,
   reconcile ownership and review the integrated diff before validating again.
   A rejected push never permits force-push. Send the final dev SHA and release
   notice to both chats when the batch lands.

The grammar-projection follow-up chat released its proposed third slot and
`source_content_pattern` reservation after rejecting both private prototypes.
Do not integrate `e35be2a7`: its macro capture unwraps `at`/`src` around
arguments and changes String-callee dispatch relative to the original branch.
The other equivalent prototype added machinery without useful simplification.
There is no publication dependency on that chat. Current order remains
Wave 5 -> aggregate batch.

This is an agreed event order, not an invented wall-clock reservation. No
aggregate publication precedes the Wave 5 landing and explicit release.
Planning and isolated work outside its files may proceed meanwhile.

For implementation, use isolated workers with one owner per file: one worker
for capture/template infrastructure; one sequential adopter worker for
`expressions.x`/`literals.x`; one independent reviewer for evidence and corpus
coverage. The orchestrator owns integration, generated output, performance,
the final gate, and publication. Workers do not gate or push. Read the current
orchestration skill at implementation start; do not add new recurring process.

## Connected implementation

### 1. Reproduce and repair capture publishing

The populated sole `Expr $items...` failure is reproduced on current dev
using a call-shaped template, independently of new Array syntax. Extend that
regression to empty sequences and the Array adopter. Compare `Macro.pattern` matching
with the public case path and inspect capture layout, not merely match success.
Repeat after Wave 5 integration if the relevant owner changes.

Fix the logical binder layout in `lib/meta.x:_macro_publishing`. The synthetic
`(!and *items)` is not a legal Match operator pattern. Use `MatchCaptureLayout.analyze(names)` for the ordered binder list. Its
lexical binder order agrees with the compiler's `(!and x2c-dyn @labels)`
pattern: the leading literal adds no binder. Verify slot number, order,
repeated names, and definite captures across runtime publishing and generated
case locals. Both pending and expanded routes share `_macro_publishing`; no
emitter edit is currently indicated. Use existing
`MatchCaptureLayout` operations. Do not weaken Match's validation to accept a
malformed operator, special-case Array, or add another layout cache.

Cover sole sequence, scalar plus sequence, repeated binders, zero binders, and
empty captured sequence; exercise pending invocation and expanded canonical
input. Include existing Name/fixed-local behavior because current dev changed
that route after the original failure. Repeated binders must retain their
existing equality/identity policy.

### 2. Finish Array adoption on released source

Port the Expr sequence parser capability by behavior into the current quoted
Array parser. Keep normal collection syntax and interpolation unchanged;
`${$items...}` is not silently redefined as an Expr sequence position.

Place the shared Array source template in the established grammar owner if
used across files; do not duplicate it in each adopter. Replace the direct
pattern workaround with the repaired macro-valued case. Retain root type,
source wrappers, child binding identity, and the existing resolution order.
Use `Compiler.rebuild_expression` after resolving children. Construct empty
Array with an empty List, not a null macro argument: the latter previously
produced an invalid one-element initializer.

Keep empty collection converter selection lazy and in its existing order.
Do not derive a fresh match pattern on every common expression or build an
Array candidate before knowing it is needed. Measure the finished path.
Record the raw constructors left only in primitive parsing as intentional.

### 3. Complete Map recognition, rows, and reconstruction

Use the proven `Entry $rows...` source template for the outer Map. Preserve
`evaluate_macro_rows` before `resolve_map_entry`, including sequence expansion
and source order. Resolve each key and value through the existing owner.
Rebuild the typed outer expression with the existing stage-preserving API.
Adopt the same template for empty Map construction without changing `{}` target
selection, Var default, or custom converter precedence.

Account explicitly for the `map-entry` constructor in `resolve_map_entry`;
outer-only adoption does not establish that row reconstruction is covered. Define a source Entry template with expression holes
for key and value. First test existing structural template expansion on an
Entry result: it must retain the supplied resolved objects and must not bind
again. If the existing expression wrapper is the only public rebuild boundary,
factor its existing structural implementation into the smallest AST-kind
operation needed by Entry, keeping expression/statement/function behavior. Prove this with the Entry
adopter before adding an API, and compare before/after code, concepts, and
actual reuse against the existing two-line semantic reconstruction. If it adds machinery without a useful semantic
boundary, retain the primitive row constructor and record that exact boundary;
do not represent it as migrated.
Do not wrap Entry in a fake Map and unpack it or add a second resolver.
Parser Entry construction stays primitive.

Check empty, single, and multiple entries; pending/computed Entry sequences;
quoted and constructed canonical inputs; duplicate-key behavior; ordered key
and value effects; typed Map conversion; empty target selection; and retained
binding identities. Expected semantics come from the current baseline.

### 4. Add the String segment capability and adopt the family

Start from a real mixed literal containing static text, named interpolation,
braced expression interpolation, numeric and custom String conversions. Also
include constructed `segraw`, which the transform owner accepts even though
the source parser does not produce it. Show
its current parsed, deferred, resolved, and runtime-literal forms. Include
empty String and the single cached-segment fast path.

Cache rows and the `segvar`/`segexp` distinction must survive. Use an existing
List metafunction to own the canonical `segments` envelope and compose its
pattern and construction at the current callers. No Segment parameter role
or new interpolation spelling is required.

Match and reconstruct complete segment rows, preserving their tags, cached
identities, and established children. Keep segment conversion in
`convert_segment_to_string`; preserve deferred `<macro-expr>` typing and source
order. Use source templates for semantic recognition and reconstruction once
the row capability is proven. Keep parsing, cache creation, empty `(0)`, and
single-cache representation selection in their current primitive owners.
Do not normalize every String to `segments` just to simplify matching.

The existing-syntax mixed literal probe establishes feasibility. Verify
canonical row and child identity at the adopted owners, then exercise the
existing String conversion fixtures. Stage the metafunction in the linked
meta seed before compiling its pattern callers; an old seed's fallback
diagnostic does not reject native List metafunctions.

### 5. Integrate, review, and correct the authored diff

Combine infrastructure and adopters after peer file release. Refresh from the
agreed dev tip, audit every remaining raw aggregate constructor by owner and
stage, and account for Array, Map/Entry, and all String representations.
Preserve Wave 5's organization. Remove temporary matching workarounds and any
superseded private helper. Update the book for actual new syntax and its
supported boundaries, using executable examples.

Have an independent reviewer inspect current code and reproduce consequential
findings. Fix the completed authored diff before publication validation.
A source-count reduction alone is not evidence of preserved behavior.

## Validation and delivery

- First retain a failing capture regression on current dev and show it passing
  after the owner repair. Test generated macro-valued case code as well as the
  native capture API; either layer can have a different logical layout.
- Extend the existing bound-template probe for root type, source wrapper,
  resolved binding and child identity, and unresolved child resolution. Add
  focused semantic fixtures for Map rows and mixed Strings as described above.
  Use existing fixture/probe infrastructure rather than a new test runner.
- Re-run `bracket-array-parity`, `quoted-collections`, `macro-array-sequence`,
  `array-default-literal`, and `macro-construction-regressions`, plus relevant
  current macro-case, Map, and String fixtures. Preserve checked-in expected
  output unless the authored behavior deliberately changes it.
- Compare baseline and candidate generated output for the representative
  corpus, then native output and side-effect order. Investigate differences;
  do not demand compiler-wide textual equality across unrelated dev changes.
- Bootstrap in order: introduce capability with a compiler that can consume
  it, regenerate through documented targets, then adopt it. The final tree
  must rebuild from its shipped bootstrap. A local-seed stage comparison alone
  cannot satisfy publication. Never edit generated bootstrap by hand.
- Measure the coherent candidate against the agreed baseline on the same host
  in the reserved quiet window using the current performance-checkpoint
  guidance. Include common expressions and aggregate-heavy translation to
  expose pattern derivation and eager rebuild costs. Record raw measurements,
  uncertainty, and any confirmed regression; do not invent a new threshold.
- Review generated deltas and run `git diff --check`. Announce the candidate
  and baseline SHAs. Use the current `tools/land-dev` publication path, which
  owns `tools/gate-state.py ensure agent-pr-check`; do not duplicate its broad
  components just to publish. Stop on a failing required check and retain logs.
- Verify the published dev SHA, update this plan with results and remaining
  boundaries, and notify both pinned chats. Archive only when all three
  families and the capture repair are delivered and verified. An intermediate
  batch may land if useful, but leaves this plan active with explicit work left.

## Design review

Reuse: source templates, MatchCaptureLayout, ordinary child resolution,
macro-row evaluation, stage-preserving rebuild, conversion, and cache owners.
Deletion: raw semantic outer constructors, duplicated structural recognition,
and the temporary direct-pattern Array path. Entry rebuild and String ownership
must earn their scope with the concrete adopters above. No origin tracking,
parallel semantic validator, new recurring gate, or broad cache redesign.

Entry remains the documented primitive row boundary. String uses existing
metafunctions; no public spelling or role decision remains. Verify the final
adoption while preserving existing semantics throughout.

Independent review: Sol reviewed capture ownership and aggregate coverage;
the pinned dual-macro coordinator reviewed campaign alignment and schedule.
Their Entry complexity boundary and explicit String public-syntax decision
are incorporated. The current-dev capture reproduction was independently
rerun by the orchestrator (`direct=1 case=0 pending=0`, malformed logical
layout versus ordinary slot 0). Repair, final bootstrap proof, performance,
and publication remain future implementation work.

## Implementation checkpoints

- `a6df045ebef8c9b11f06d06040f65b0c175c6ae0`, based on `d537e8d8`:
  capture publication uses `MatchCaptureLayout.analyze(names)`. The new
  `macro-sequence-case` fixture fails before the repair and passes afterward;
  covers empty/populated, pending/expanded, mixed, reordered, repeated, and
  zero-binder cases. Existing `macro-mixed-name-case` and `macro-values` pass.
  The orchestrator reviewed the authored diff and independently reran the new
  fixture successfully with separate temporary output. No publication gate.
- `f867642a6b4054d14e99f2019ccbcfdf5980a491` adds Array sequence parsing
  on top of the capture repair in current `literals.x`. Its fixture failed
  before the change; it and `quoted-collections`/`bracket-array-parity` passed
  afterward. The orchestrator independently reran `macro-array-sequence`
  successfully. Array/Map semantic adoption is proceeding
  in the existing isolated adoption tree; final port waits for Wave 5 release.
- String investigation identified a further requirement: a public Segment
  parameter needs an ordinary invocation argument contract, not just a hole
  spelling inside a String template. Do not present the template spelling as
  a complete public design. The design worker is resolving that contract.

### Withdrawn String public contract (historical proposal)

The following proposal was withdrawn in favor of existing metafunctions.
It is retained only as the history of the superseded design.

`Segment` represents one complete String row. An ordinary argument is a
percent String fragment containing exactly one row: `%"text"`, `%"$name"`, or
`%"${count}"`. A variadic parameter takes zero or more comma-separated
fragments; `$join()` supplies zero. Empty and multi-row fragments do not
satisfy a single Segment argument. Programmatic macro-value calls may supply
canonical rows, including constructed `segraw`, as other row kinds do.

Proposed definitions and calls:

```text
macro Expression $join(Segment $rows...) => %"prefix${$rows...}suffix";
macro Expression $wrap(Segment $row) => %"<${$row}>";
$join(%"a", %"$name", %"${count}")
$wrap(%"text")
```

The argument parser uses the existing String parser and projects its one row;
the template parser recognizes only registered Segment holes after `${`.
Existing expression interpolation retains its meaning. No tokenizer change is
needed. Changes belong to macro kind/role/argument handling, String template
parsing, the grammar adopter, and documentation/fixtures. This contract is a
proposal, not implemented syntax. A temporary existing-syntax row rebuild
probe produced `aN2b`; new-kind roundtrip and performance are still unproved.

- `51309e98be118c50ca71b11403fab8af669d1172` repairs a reproduced existing
  constructed `segraw` code-generation defect: the C literal lacked its type,
  causing an argumentless `String_new()`. The focused native fixture fails
  before the fix and passes afterward; three neighboring String fixtures pass.
  The orchestrator reproduced the failure on the current-dev-based compiler,
  reviewed the one-line fix, and independently reran the passing fixture.
  This changes no public Segment syntax and awaits the Wave 5 transform release.

- `5ec79ed9490ba7a148a972973cdc46525ef64843` completes isolated Array/Map
  outer semantic adoption, on old adopter base `9356cc12` plus capture repair
  dependency `5977ba5c`. Shared templates replace the direct-pattern workaround;
  root-tag dispatch preserves wrapper boundaries, and empty construction stays
  lazy in Map-first order. Entry reconstruction remains the explicit primitive
  boundary. Nine existing fixtures, two new semantic fixtures, and the native
  bound-template probe pass. The new converter/order programs also pass the
  baseline seed with identical output. Root independently compiled and ran
  the native probe and reran both new fixtures successfully. The local build
  used a capable seed; shipped-bootstrap and final integrated-tree validation
  remain outstanding. Independent authored-diff review found no concrete regression; it inspected
  wrapper boundaries, Map row order, and lazy converter precedence and reran
  the native probe. Whole-corpus output and performance remain integration work.

## Integration and publication candidate

Wave 5 explicitly yielded its slot: aggregate now integrates on `7aac075e`
and publishes first; Wave 5 will merge this result afterward. Its measurements
are paused for this build/gate window. The new public Segment proposal remains
awaiting Gary's decision and is not included in this settled batch.

The integration safe build and capability-seeded adopter build passed.
The native identity/resolution probe and six focused capture, collection,
converter-order, and constructed-String fixtures passed on the integrated tree.
The book documents the implemented quoted Array sequence position.

Performance used the same seven-source baseline corpus and interleaved compiler
runs. Initial unequal executable paths measured +0.89% and +1.38% instruction
medians. A crossover with equal-length executable paths and alternating output
locations measured -0.086%, with paired differences of both signs. These data
show no robust increase under the corrected setup and do not establish an
improvement. All generated C/H matched for the corpus. Raw observations remain
in `debug/aggregate-performance*.json` and corresponding logs. A speculative
dispatch rewrite was not built and is excluded. Final publication validation
must still establish rebuildability from the shipped bootstrap.

## Delivered result

Verified `origin/dev` at `7699e2772cb293481ea0b3bd554d304cb1067a3a`.
The publication gate is valid for that unchanged tree: 904 compiler fixtures
(2068 artifacts), 912 unit tests (20373 assertions), documentation, CLI/state,
stage comparisons, and remaining command checks passed. Generated bootstrap
was refreshed with the documented target using a capable seed, then the gate
rebuilt from the shipped bootstrap. The initial publication build stopped on
the old seed's Array syntax; that transition was repaired before publication.

Array and Map use the shared source templates. Map Entry reconstruction and
primitive parsers remain documented boundaries. The sole-sequence capture
repair and constructed `segraw` native repair are shipped. Segment signature,
argument syntax, and String source-template adoption remain unimplemented;
this plan stays active for that explicit remaining decision and work.

Wave 5 resumes after this batch's release and must integrate the landing tip.

## String decision and campaign completion

Gary identified ordinary metafunctions as the appropriate tool. A native
probe using existing `Expr` parameters and meta List composition accepts whole
interpolated String literals, handles empty and static forms, and preserves
mixed text, named interpolation and numeric conversion. It printed
`Result: Hello Gary - 3` and passed its runtime checks. The proposed Segment
kind and one-row argument contract are withdrawn; no public syntax decision
is pending. The remaining String implementation uses existing metafunctions
and canonical row semantics.

Gary authorized this orchestrator to finish the entire campaign, with Sol
medium workers. Current baseline is Wave 5's released `0bccd679`. Independent
coverage surveys found expression, truth-conversion/return, region, and
native builtin builder families that earlier E43 did not close. These are
being implemented in isolated owner groups; the campaign handoff and inventory
will be reconciled against the final source. Completion requires delivered
work and explicit evidenced parser/semantic/backend boundaries, not treating
a prior no-candidate survey as proof.
