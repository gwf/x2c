# Language component foundation

> Status: active
> Branch `codex/language-components-foundation`, started from dev
> `7e946b86663f9f069fe14e284c41e2aed73c57e0`. Gary authorized publication to
> `dev` on 2026-10-09 after Milestone 0, the three component cases, `try`,
> and the driver work; this plan records what landed and owns the
> extraction order that follows. `main` is untouched.

## Goal and current boundary

Move language policy out of the compiler when ordinary component authoring makes
the complete implementation simpler. Use decorators, reusable macro patterns,
quotations, and Code/Type methods. Keep binding, typing, evaluation order,
statement placement, and lifecycle correctness with their existing owners.
Judge the entire authored change, including library and support code; a smaller
kernel alone is not proof of simplification.

The current foundation preserves the Array/Map mutation component and 17
optional examples across access, declarations, dispatch, and delegation.
`$auto`, recursive delegation, and try cleanup retain dev's implementations.
The examples for selected-type cleanup and one wrapper's delegation are bounded
proofs, not complete builtin replacements.

## Recovery scope

Preserved from `gwf/language-components` at `5b7a7769`:

- Ordinary rewrite registration, prepared macro matchers, binding identity,
  user-before-builtin precedence, and active-rule suppression.
- Shared Code/Type operations and required compiler/helper support.
- `src/component-access.x` and the compiler's operation dispatch points.
- Header declaration ownership repair, which removes redundant prototypes
  without replacing bound helper calls with raw names.
- Optional examples, focused fixtures, and historical measurement reports.

Excluded from the active implementation:

- Hook syntax, hook registry, initializer claims, component-auto, and
  component-delegate. Dev's complete semantic owners remain in service.
- Delegate-only fact/query APIs and the experimental generic try-region
  forms. Dev's cleanup lowering and lifetime analysis remain.
- The failed temporary `$auto` boundary implementation and the speculative
  kernel-minimal architecture campaign.

Original refs remain intact. Historical plans are preserved in
[experiments](archive/language-components-experiments.md),
[authoring](archive/language-components-authoring.md), and
[kernel hypotheses](archive/compiler-kernel-hypotheses.md).
Their instructions, future-tense tasks, and projected savings are historical.
Raw copied evidence lives under `.context/language-components/`; bootstrap
transition and recovery logs live under `debug/foundation-*`.

## Evidence and acceptance

The regenerated bootstrap reproduces all 262 stage-0 C/H files. All 1,111
fixtures pass when checked individually, including the five failures recorded
on the prior branch. All 17 optional examples pass. Runtime checks pass 942
tests / 25,024 assertions and 23 thread tests / 89 assertions. Documentation
checks pass. The complete `make verify` target passes, including 2,484
fixture artifacts and its CLI, cache, protocol, package, and boundary probes.

Two declaration corrections preserve existing behavior. A captured Unit keeps
its initializer during collection. Unit decorators are tried through the
existing speculative collection owner; a form that needs the full parse can
fall back there. This restores nested decorator initializers and the deliberate
foreign-alias-body diagnostic. `rewrite-stacked` checks that all three
registrations on one function survive an included provider's collection.

Native synthetic C/H is byte-identical to exact dev. Collection headers and
function bodies are identical; C removes seven redundant prototypes.
All 131 changed C fixture expectations differ only in prototype and blank-line
removal. The compound-update transform records bound helper references. The
`class-runtime` warning now points to the header declaration. The only changed
AST expectation, `keyword-aliases`, renumbers internal origin IDs by four.
No program output or rejection expectation was weakened.

Twelve repeated generations keep all 18 C/H/.xi artifacts identical, totaling
14,848 bytes. Fresh-process provider replay is identical. Cyclic inline headers
compile with `-Werror` and run. Three meta-helper generations return the same
constant and retain identical cached C/H/.xi hashes. These bounded checks do
not establish a universal limit for every possible macro program.

Evidence is under `.context/foundation/` and `debug/foundation-*`. The
`fixtures.json`, `fixture-c-review.json`, `bounded.json`, and synthetic
comparison record the current recovery. Copied historical reports retain their
original revision labels. The temporary `$auto` prototype's successful small
probes do not establish a complete replacement.

## Source cost

Physical authored lines against dev `7e946b86`, including comments and blanks:

| Area | Added | Removed | Net |
| --- | ---: | ---: | ---: |
| Compiler, excluding generated linked-meta and builtin component | 591 | 745 | -154 |
| Builtin collection component | 132 | 0 | +132 |
| Library | 737 | 13 | +724 |
| Build/helper/support source | 132 | 72 | +60 |
| Implementation total | 1,592 | 830 | +762 |
| Tests and executable examples | 1,542 | 3 | +1,539 |

The implementation is 301 lines smaller than `5b7a7769`, but remains 762 lines
larger than dev. Moving 617 Type lines into the library accounts for much of
the kernel reduction. This is a working foundation, not a demonstrated total
source reduction. Generated compiler/runtime artifacts and fixture expectations
are counted separately in `loc.json`; their deletions are not authored savings.
Archived plans are historical evidence, not implementation cost.

Fresh warm synthetic translation against exact dev, seven alternating pairs,
`-j 1`, same absolute inputs/output directory and toolchain, after verification:

| Workload | Dev median seconds | Foundation median seconds | Ratio |
| --- | ---: | ---: | ---: |
| Native arithmetic and indexing, 300 functions | 0.274596 | 0.299947 | 1.092 |
| Collection access, 120 functions / 5,400 mutations | 0.634581 | 0.942410 | 1.485 |

Samples and compiler hashes are in `.context/foundation/synthetic/time/`.
This is elapsed translation time, not instruction count, runtime speed, cold
start, or whole-build performance. The collection cost remains substantial.
No representative compiler-build performance result is established for this
foundation; that measurement and profiling remain necessary before accepting
the combined architecture. Recovery establishes a working basis, not a
performance acceptance decision.

## Decisions of 2026-10-09

Gary accepted [the kernel analysis](compiler-kernel-minimal.md) as the
design: two primitives, recognition through rewrite families and
contribution through placement and ancestry, with the kernel's own lowerings
as their first clients. He decided:

- `$auto` keeps its spelling and becomes an ordinary macro on
  `enclosing(<declarator>)` and `place(<after-statement>)`; the
  `managed-init` marker and its recognizers go.
- `try`, `catch`, and `finally` become a component on the `block-exit`
  placement, with the cleanup walk as that point's scheduler and the landing
  as the only try-specific part.
- The token statement parsers get a measured unification prototype against
  the constructed-form binder.
- The initial scope is ten recognition families, six placement points, and
  five ancestors. A lowering that needs another presents it first.
- Implementation workers run on Opus; the orchestrator integrates here.
  Publication stays held; everything remains local on this branch.

## Milestone 0: the primitives and the driver

Runs before the milestone below, in parallel worktrees branched from this
branch, integrated here in one batch:

1. Driver cost. Profile the empty unit's 0.34 G fixed cost and remove it with
   a process-scoped rule table; call linked translators through their `Func`;
   decline by void or NULL with an identity test; match once. Guard: the
   empty unit within one percent of dev, the access workload at or under dev.
2. Primitives and `$auto`. `x2c_enclosing(what)` for `declarator`,
   `statement`, `function`, and `unit`; `x2c_place(where, code)` for
   `after-statement`, `unit-support`, and `unit-init`, applied under the
   expansion's transaction through the existing code-value effects. Port
   `$auto`; delete `managed-init` and its five recognizers; keep every
   managed-init diagnostic and byte-identical C.
3. Binder prototype. `if`, `while`, `do`, and `for` parsed to canonical
   unbound syntax and bound through `_bind_form`; measure a self-translation;
   report the number and recommend.
4. After 2 lands: `defer` as the kernel's `block-exit` placement, the
   cleanup walk as its scheduler, `x2c_place(<block-exit>)`, and
   `src/component-try.x` on it, with the spike's try component
   (`gwf/hooks-spike`, W4-A) as the reference. Guard: byte-identical C on
   the corpus and the try fixtures.

### Milestone 0 results, 2026-10-09

Items 1 to 3 are integrated on this branch at the commit after this one.
Items landed as sixteen authored commits from three Opus worktrees plus one
generated refresh; `make verify` passes (1,114 fixtures, 942 unit tests,
probes), 17 of 17 optional examples pass, and bootstrap equals stage 0
across 262 C/H files.

- Driver. The 0.34 G fixed cost was mostly a defect: the shipped
  component's `.xi` could not be read back because a `<<=` Symbol in a
  rewrite effect row did not round-trip through the datum writer, so every
  translation walked `src/component-access.x` cold (about 0.29 G). Effect
  rows are now frozen for interfaces; shipped rules are thawed once per
  process and their matchers derived on first probe; linked translators are
  called through their `Func`; declines test identity; the runtime
  declaration inventory is read once per entry. The second match inside a
  translator (about 35 K per application) was measured and left, because
  removing it changes the translator contract.
- Primitives. `x2c_enclosing(what)` for `declarator`, `statement`,
  `function`, `unit`, and `x2c_place(where, code)` for `%(after-statement)`,
  `%(unit-support [KEY])`, `%(unit-init [AREA])`; `where` is a List because
  Symbols hold ten characters. `$auto` keeps its spelling on them through a
  linked release macro; `managed-init` and its five recognizers are gone.
  Checks run at declaration completion so the eight managed-init fixtures
  keep their diagnostics. Per use: +28 K instructions over the baseline on
  an 11.3 M `defer` lowering. `$auto` arguments now receive the ordinary
  unnecessary-conversion warning; seven `.array()` calls in lib were
  removed with byte-identical C.
- Binder. `if`, `while`, `do`, and `for` enter the constructed binders
  directly with deferred children marked by a static Token table that Lisp
  cannot construct. Per statement within noise; self-translation +0.04
  percent; +47 source lines, mostly one-time machinery. Extension to other
  statements awaits Gary's decision; `match`, `catch`, and `with` are the
  candidates that would delete lines.

Fresh translations against dev, instructions retired, median of 3:

| Workload | dev | before milestone 0 | after |
| --- | ---: | ---: | ---: |
| Empty unit | 1.94 G | 2.30 G | 2.06 G |
| Native, 300 functions | 4.22 G | 4.59 G | 4.34 G |
| Access, 5,400 mutations | 10.30 G | 14.71 G | 14.37 G |

Authored src/lib/etc lines: 640 added, 226 removed. The remaining fixed
cost is reading the component interface (about 0.06 G) and effect install;
the remaining access cost is binding each replacement, which is the
prepared-replacements work. Item 4, `try` on `block-exit`, starts from
this head.

### Milestone 0 item 4 and the binder extension, 2026-10-09

Integrated on this branch after the results above; `make verify` passes
(1,115 fixtures, 942 unit tests, probes), 17 of 17 examples pass, and
bootstrap equals stage 0 across 264 C/H files.

- `try`, `catch`, and `finally` are lowered by the shipped component
  `src/component-try.x` (274 lines), registered through `$rewrite` on the
  `try` statement head and dispatched where the cleanup walk met `try`. The
  kernel keeps one generic form, `(landing CODE ROWS)` with `new-name`,
  `outer`, `exits`, and `region` rows, which the component returns as a
  lowered code value; Preserve, label collection, and the statement
  expression test read only the rows. `src/cleanup.x` went from 1,417 to
  1,256 lines; kernel and SDK together lost 144 lines, kernel plus component
  grew by 130. Per `try`: about +0.3 M instructions, under the spike's
  0.73 M. Byte-identical C on all 72 try, catch, defer, raise, cleanup,
  exception, and volatile fixtures and on every unedited module.
- Two findings. The try body and arm regions do not use `%(block-exit)`:
  a `defer` lowers to a runtime cleanup record and thunk, while try's exits
  are lexical, so the C would differ. `%(block-exit)` exists (it contributes
  `(defer STMT)` after the statement; fixture `meta-place-block-exit`), but
  the shared primitive between `defer` and `try` is the region form, not
  the placement. And `src/grammar.x` had to become a prelude source so the
  component's `$tried` and `$caught` recognizers resolve in every unit; the
  kernel's `defer` still produces a `try` form on its landing path and so
  depends on the shipped component.
- Binder extension: `match` and the `try` statement enter the constructed
  binders directly; `bind_match_arm` and `bind_catch_arm` are the one
  implementation of arm binding for source and constructed syntax. `with`
  has no constructed form and was left alone. statements.x lost 52 lines,
  parse.x gained 71; self-translation within noise.

Fresh translations against dev, instructions retired, median of 3:

| Workload | dev | after milestone 0 items 1 to 3 | after this batch |
| --- | ---: | ---: | ---: |
| Empty unit | 1.96 G | 2.06 G | 2.13 G |
| Native, 300 functions | 4.21 G | 4.34 G | 4.43 G |
| Access, 5,400 mutations | 10.28 G | 14.37 G | 14.48 G |

The added fixed cost (about 0.07 G) is reading `grammar.x` and the try
component as prelude sources; it belongs to the driver work, together with
the remaining access cost, which is binding each replacement.

### Milestone 0 items 5 and 6, authorized 2026-10-09

Gary authorized both remaining driver costs, in parallel worktrees from this
head, integrated here as one batch:

5. Prepared replacements. A translator's quotation is bound once per template
   and hole-type signature into a bound skeleton; each use substitutes the
   bound hole values. Guard: the access workload moves toward dev's 10.28 G
   with byte-identical C; `try` and `$auto` stay at or under their current
   per-use cost.
6. Linked prelude. The shipped components' collected interfaces are compiled
   into the compiler rather than read from `.xi` files per process. Guard:
   the empty unit moves toward dev's 1.96 G; `make stage-3` wall time moves
   toward dev's 13.2 s (foundation: 14.1 s); package-install and header-cache
   probes pass.

### Item 5 result, 2026-10-09

Prepared replacements are integrated at the commit above this one;
`make verify` passes (1,115 fixtures, 942 unit tests, probes), 17 of 17
examples pass, bootstrap equals stage 0 across 264 files, and generated C is
byte-identical for both synthetic workloads and for all of lib and src.

The driver lowers a rewrite's replacement once per unit while watching which
typed source expressions it consumed, keeps the lowered result as a skeleton
with slots when that lowering was pure (no introduced binding, name, origin,
placement, or diagnostic), and fills the skeleton on later uses after
lowering only the slot values. The memo key is the position, the expected
type, and the template with each slot reduced to its type and a small shape
(`Compiler._slot_shape` in src/macros.x): a literal's value, an identifier
with its lambda-snapshot status, the head of a call, index, postfix, or
cast, an operator with a unary operand's shape, a member access with its
base's shape, or a group's inner shape; a conditional, comma, composite,
collection literal, interpolation, or statement expression refuses. The
shape list is derived from what `convert_expression` reads and proven by
the byte-identical results, not by construction; an unlisted shape refuses,
so a miss costs speed, not correctness. All of component-access.x's
quotations prepare; component-try.x returns lowered code and is unaffected.
macros.x gained 280 lines.

| Workload | dev | before | after |
| --- | ---: | ---: | ---: |
| Access, 5,400 mutations | 10.30 G | 14.47 G | 10.19 G |
| Empty unit | 1.97 G | 2.15 G | 2.15 G |
| Native, 300 functions | 4.23 G | 4.44 G | 4.44 G |

The translator call is now the largest remaining per-use cost (about 77 K of
213 K per application): its own match, quotation building, and the Lisp
session setup per call.

### Item 6 result, 2026-10-09: held on `kernel/linked-prelude` at 19236c74

The three shipped components' collected records are linked into `collect.c`
as a literal Map built by a compile-time builtin during the translation of
`collect.x`, read before the `.xi` lookup with the same staleness checks, and
their rules installed once per process. It also fixes a determinism defect in
`grammar.x`'s collected dependencies. Byte-identical C, 1,115 fixtures,
`make verify`, the five home-building probes, and an installed-home run pass.

| Measurement | before | with | dev |
| --- | ---: | ---: | ---: |
| Empty unit, repository build | 2.16 G | 2.04 G | 1.96 G |
| Empty unit, installed home | 2.49 G | 2.06 G | |
| `make stage-3`, median of 3 on a loaded machine | 15.5 s | 16.0 s | 15.3 s |

It trades per-process cost for per-stage cost: `collect.c` grew from 175 KB
to 443 KB, its translation walks the three components, and its `-O2` compile
takes 0.5 s longer in every stage, while a stage batch saves only one prelude
read. The stage-3 guard was missed, so integration awaits Gary's choice:
take it as is, take it after a cheaper emission of large literals, or leave
it out. Component sources stay in the installed home for hashing, depfiles,
and the cold fallback. Folding `lib/x2c.x` (about 1.47 G of every empty unit,
paid by dev too) into the same table is the larger prize and the same trade,
and is also Gary's decision.

### Item 6 result, 2026-10-09: integrated with cheaper emission

Gary chose the linked prelude with a cheaper emission. It is integrated at the
commit above this one; `make verify` passes (1,115 fixtures, 943 unit tests,
probes), 17 of 17 examples pass, bootstrap equals stage 0 across 264 files,
`tools/check-cold-collection.sh` passes, and an installed home builds and
runs a program using `$auto`, `try`/`catch`, and an Array store.

The three components' records are three C string literals in `collect.c`
(270 KB, compiled in its old 0.29 s), read once per process by the interface
reader with the same staleness checks and fallbacks. Meeting the empty-unit
guard needed a second change, which goes beyond the component work and is
flagged for Gary's review: `datum_read_plain` in `lib/datum.x` reads the
spellings `datum_write` makes for plain data (Lists, Strings, decimal
integers, bare Atoms) without the Lisp tokenizer, falling back to `Lisp.read`
for anything else. Every `.xi` read uses it, so the gain reaches dev's own
cost. Equivalence was checked against `Lisp.read` over all 268 interface forms
in two stage directories plus 475 edge spellings, one edge (an Atom beginning
with a comment opener) was fixed, and `lisp_plain_datum_read_matches_reader`
covers the edges. A pre-existing defect remains: `Atom.bare_spelling` accepts
spellings beginning with `//` or `/*`, which the Lisp reader reads as comments.

| Workload | dev | before item 6 | after |
| --- | ---: | ---: | ---: |
| Empty unit | 1.96 G | 2.15 G | 1.32 G |
| Native, 300 functions | 4.23 G | 4.45 G | 3.61 G |
| Access, 5,400 mutations | 10.30 G | 10.20 G | 9.35 G |
| Empty unit, installed home | | 2.51 G | 1.34 G |
| `make stage-3`, one run on the integrated tree | 13.2 s | 14.1 s | 13.2 s |

With the cheap reader the linked table itself pays only in an installed home
(0.38 G per translation, which ships no component `.xi`); in the repository
layout it is neutral and costs a 0.45 G component walk once per stage.
Shipping the component interfaces in the home instead is an unevaluated
simpler alternative. Folding `lib/x2c.x` into the table is no longer the
prize it was, since its `.xi` reads are now cheap.

### Delegation and two repairs, 2026-10-09

Integrated at the commit above this one; `make verify` passes (1,115
fixtures, 944 unit tests, probes), 17 of 17 examples pass, and bootstrap
equals stage 0 across 266 files.

- Delegation runs in `src/component-delegate.x` (134 lines); the kernel lost
  80 lines (`DelegateSearch`, the `delegate` resolution arm,
  `_completion_delegates`, two report macros, `declare_delegate_field`).
  Registration is keyed by a declaration-time fact, not by a parse-time rule
  copy: a rule registered when the parser saw the field never reached an
  importing unit, because interfaces and packages copy Sym rows and never
  run the importer's rule table. So the parser records a general field mark
  (`Sym.mark_field`, with a per-aggregate `(AGG delegate)` row that crosses
  interfaces), and the component registers once on the mark with
  `$rewrite_marked(<delegate>, f)` over `Code.register_marked_rewrite`; a
  lookup miss checks the receiver's aggregate marks after the `member` family.
  New SDK queries: `Type.aggregate`, `Type.marked_fields`,
  `Type.resolve_member`. Byte-identical C and diagnostics on 52 fixtures and
  extra probes. Documented changes: a member rewrite for the receiver's own
  type now precedes delegation; missed member calls in `meta` bodies now reach
  member rules. Delegated completion was dead at baseline (added, then
  filtered) and is removed. Cost: direct calls unchanged; a delegated call is
  0.26 M over a direct call (kernel search: 0.09 M), mostly binding the
  rebuilt call; the fourth prelude component adds about 15 M per unit. A
  shipped component cannot call `lib/meta.x` meta builders without failing its
  linked-copy check in meta builds; the component builds lists instead.
- `Atom.bare_spelling` now rejects spellings opening a reader comment, so
  `datum_write` quotes them; unit cases in test-atom and test-lisp. The install
  payload's two explicit `.str()` conversions are gone and `make install` is
  warning-free.
- Fixed in the publication batch: `Symbol.write_repr` wrote a general Symbol
  with escaped quotes, which `Symbol.parse` and the Lisp reader could not read
  back, so untagged `datum_write` produced unreadable interfaces for `<<`,
  `<x`, `a b`, and `<<=`; and `Atom.bare_spelling` accepted a backslash the
  reader takes as an escape. The repr now writes the source literal
  `<"...">`, untagged `datum_write` refuses the empty Symbol (which has no
  plain spelling) instead of writing `<>`, and bare spellings reject every
  backslash. Unit cases in test-symbol, test-lisp, and test-atom. The
  interface writer does reach this path, so the rewrite-row freeze stays: the
  rows hold the empty Symbol `(target <>)`, which was the malformed read the
  driver work attributed to `<<=`, and an unfrozen `<"<<=">` kind would send
  the whole record to `Lisp.read`, 3.5x slower than the plain reader.

Milestone 0 and the milestone below's items 1 and 2 are complete. Authored
src, lib, and etc against dev: 4,000 added, 1,663 removed, of which 617 are
the `type.x` move to the library. The three component files hold 540 lines;
the kernel's feature files lost 159 (expressions), 280 (cleanup), 152
(statements), and 12 (expressions-reports); the mechanism grew macros.x by
577, parse.x by 398, collect.x by 208, and meta-sdk.x by 185.

### Repairs after publication, 2026-10-10

Gary repaired four defects on `dev` after the publication (d7a652ee through
d93b759b): the plain datum reader accepted one nesting level more than
`Lisp.read` and bounded integers by digit count (ours); a user `$rewrite` on
`try` returning ordinary code was dropped by `_landing_form`, whose fixtures
covered only the landing form (ours); `_subject_globals` walked a rewrite
subject recursively, and the access dispatch made that reachable at every
indexed store, so a 50,000-term chain overflowed the stack (exposed by ours);
and a provider whose declaration collection ran project meta code was replayed
from cache, losing its effects (pre-existing; the probe fails on the pre-batch
dev compiler too). Two rules for every later worker brief: no recursive walks
over expression chains, and a rule's fixtures include a user component that
returns something the shipped component does not.

## The campaign from here

The mechanism is built and paid for. From this point each move takes one
feature out of the kernel as a component on the two primitives, deletes the
kernel arms, report macros, and `Compiler` fields it owned, and lands on `dev`
through the gate with three numbers: the empty unit, the feature's own
workload, and a self-translation. A move that adds more than it deletes stays
in the kernel, and the catalog records that. The end state is a kernel of
parser, binder, conversion engine, cleanup walk, macro substrate, unit
assembly, and the rule driver, with every language feature a file under
`src/component-*.x` that a user could have written.

### Migrations to deliver, in order

| Feature | Family and placement | Kernel lines | Uses in src and lib |
| --- | --- | ---: | ---: |
| printf Var formats | call, by callee binding; delivered in wave 1 | 380 | 260 |
| raise | statement; delivered in wave 1, simplification follows | 200 | 416 |
| collection literals and literal order | literal, by head; delivered in wave 1 | 290 | many |
| destructuring | statement, plus the function pre-pass | 330 | few |
| string interpolation | literal `segments`; delivered in wave 2 | 200 | 730 |
| truthiness, getindex, dynamic operators | unary, binary, access; delivered in wave 1 | 410 | 620 |
| lambda lowering | function family; function-entry and unit-support placements | 1,500 | 586 |
| protocols: declarations, conformance, owners, adapters | unit declaration marks; unit placements | 1,850 | 153 |

Runtime static locals and class defaults stay in the kernel; the log of
2026-10-10 records why. `match` moves from the research list to the table
once `plans/match-component.md` is accepted.

Kernel deletions no feature blocks: the `function-entry` and
`before-statement` placements, designed but without a client until lambdas
and destructuring land. The wave 2 audit found no deletable `Compiler` field
and no per-call Lisp session setup left in the driver; the prepared
replacement template and fill steps are the remaining driver cost.

### Open, needing research before a decision

- `match`: delivered in wave 2 as `src/component-match.x` per
  `plans/match-component.md`; verbatim C text in a lowered carrier is now a
  documented kernel service.
- Kernel lowerings in the component form: the try and defer templates, the
  `Func` call construct-and-recognize pair, wrapper synthesis, and scope cells
  build AST by hand. Rewriting them as quotations needs the open-template
  rule, free names resolving at the insertion site, which is undesigned.
- Shipped components and the meta builders: a component cannot call
  `lib/meta.x` builders without failing its linked-copy check in meta builds
  (delegate built lists instead). A linked-meta provenance fix comes first.
- `defer` and the landing form: `defer` lowers to a runtime cleanup record
  and thunk while try's exits are lexical. Whether `defer` should become a
  lexical client of the same form is unmeasured for generated C and runtime.
- Conformance facts across interfaces: `Sym.mark_field` is per field;
  protocols need per-type facts that cross interfaces and packages.
- `with`: no constructed form, so unifying or extracting it adds
  macro-visible syntax, a language decision.
- The linked prelude's future: with the cheap reader it pays only in
  installed homes; shipping the component interfaces in the home may replace
  it, and folding `lib/x2c.x` is no longer the prize it looked like.

### Log

- 2026-10-10: printf Var formats started as the first extraction under the
  deletion rule.
- 2026-10-10, wave 1 (held for review on `kernel/sdk-cleanup`): four shipped
  components landed in one batch over c09d9a91. `component-printf.x` (208
  lines) owns Var formats; `component-literals.x` (47) owns Array and Map
  literals; `component-operators.x` (147) owns dynamic operators and
  participant indexing, with `component-access.x` taking bracket access for
  every participant; `component-raise.x` (97) owns raise. Kernel
  `src/` outside the components lost 906 lines and gained 491; `lib/` lost
  309 and gained 229. Gary accepted the authored growth because the
  components read as the feature's whole implementation; the deletion rule
  is now judged by kernel removed against component added, with shared
  infrastructure counted once.
- 2026-10-10, stays in the kernel: runtime static locals (the landing form
  would carry more than the arm it replaces) and class defaults (class is
  already a component; the runtime core embeds it). Both rows leave the
  migration table.
- 2026-10-10, plumbing: one `$rewrite(PATTERN, HOLES...)` decorator in
  `lib/rewrite.x` registers every family; `(!or OP...)` spells operator
  sets and typed holes give type keys. `tools/gen-meta-queries.sh` generates
  `etc/meta-queries.x`, the meta helper's forwarders, from `lib/meta.x`.
  `Code.lowered` marks a translator result as lowered; typed quotations
  produce lowered trees without it.
- 2026-10-10, SDK cleanup: public meta operations went from 62 to 49
  (Code 17, Type 20, `x2c_` 12). The 14 `x2c_expr_*`, `x2c_literal_*`, and
  `*_make` constructors are gone; quotations build what they built. The 23
  `x2c_type_*`, `x2c_function_*`, and `x2c_source_text` queries became
  `Type.*` and `Code.*` methods. Kept: `x2c_ident` (144 call sites), the
  diagnostics, invocation position, `x2c_enclosing`, `x2c_place`. Lisp keeps
  `x2c.literal.*` in `etc/compiler-sdk.xlisp` under one naming rule.
  Diagnostics now name the method. Costs against ceda17c0: empty unit -5.0%,
  native -1.2%, access -0.9%, self-translation -0.8%.
- 2026-10-10, raise follow-up: the component is kept at +24 over the kernel
  arm it replaced and is scheduled for a deliberate simplification.
- 2026-10-10, raise simplified: `component-raise.x` went from 97 lines to
  61. The static check keeps the flat type test and drops the walk over List
  contents and `*_var` boxing calls, which repeated the runtime's
  `ErrorRegion._copy_value` check at the `<bad-types>` floor. The book now
  says a value's own invalid type is a compiler error and invalid contents of
  a List or Var value reach the floor when the raise runs; the
  `raise-invalid-nested` fixture is gone, and a probe confirmed the floor
  message for its program.
- 2026-10-10, match research (`plans/match-component.md`, branch
  `kernel/match-research`): a match component is feasible at 4.75 M per use
  against 4.62 M for the kernel arm on a three-arm workload, with runtime
  3.6-10x faster than the plan cache, deleting about 334 kernel lines. It
  needs a documented verbatim-C-text emitter rule, `Code.pattern_value`,
  `x2c_fresh_binding`, match as a rewrite point, and lowered results that
  skip the prepared walk.
- 2026-10-10, wave 2 (held for review on `kernel/wave2-integration`): three
  workers from 9805f3c2, integrated as one batch.
  - `match` is `src/component-match.x` per `plans/match-component.md`, in
    two moves. Move 1 ports the emitter: kernel -340 (emit.x match section
    and templates, transform.x `_match_cases`/`_match_records`/`matchcases`,
    compiler.x flat-pattern helpers, cleanup.x `matchcases`), shared
    services +38, component 266 lines, net -30. Move 2 tests static
    patterns in place with nested `if` tests: component 392 lines, +126
    against the plan's estimate of about 65; the extra is explicit pending
    stacks instead of recursion, rollback when a pattern leaves the nested
    subset, and declaring cursors and the buffer only when used. The one
    SDK addition is `Code.pattern_value`; the plan's fresh-binding
    operation was not needed because the `_x2c_match_*` names are scoped to
    the match's block. Translation per use: W3 4.63 M -> 4.81 M (move 1)
    -> 4.26 M (move 2); W4 12.32 M -> 10.98 M -> 8.95 M; self-translation
    of expressions.x 24.66 G -> 24.71 G -> 22.66 G. Runtime: W3 1.39 s ->
    0.15 s; W4 21.5 ns -> 6.3 ns per match. The compiler's own C has 1,011
    nested-test arms, 329 static Match sites, 3 dynamic, 75 macro-valued.
  - String interpolation is `src/component-interpolation.x`, 32 lines, on
    `$rewrite(%(expr ("String") (segments *)))`; the kernel lost a net 20
    lines (the segment lowering helpers and the recursive cons builder) and
    keeps the one-constant cache shortcut, the String conversion of
    insertions, and the lifting of ordering declarations. Chains longer
    than 128 cells use `List_list_n` through `_ordered_list`, which also
    removes the old nesting-depth failure near 256 elements. The join is a
    typed quotation of `String.join`; the verbatim-text form (byte-identical
    C) is commit e99a8fe6 on `kernel/interpolation`. Workload of 1000
    interpolations: 7.61 G -> 6.90 G.
  - Kernel deletions: no `Compiler` field could go; every field named by
    the earlier count has a live reader (defer's `needs_exception`, the
    literal cache's `runtime_literals`/`id_keys`/`key_ids`, protocol and
    lambda state that has not migrated, match parse state, the driver's own
    rows, the two primitives' rows). The driver's per-call Lisp session
    setup was already gone; the trim joins library paths once per process,
    drops an empty Map per call, sends lowered results past the template
    step, and collects slot sources in one walk: bracket read 544 K -> 526 K
    per use, raise 1,294 K -> 1,258 K, byte-identical C. The largest
    remaining driver cost is the prepared-replacement template and fill
    (about 28% of the driver on bracket reads).
  - Defects found, open: a prelude component whose rule is lost during
    collection lowered its form to nothing without a diagnostic (`String s
    =;` observed); fixed 2026-10-10: the match, collection literal, and
    interpolation arms report `no rule lowers this FORM` when no rule
    answers, since the kernel has no lowering of its own for them. The
    loss itself is reproduced by a definition in the component that fails
    to collect, such as a `meta native` call, and is still silent at
    collection; `tools/gen-linked-meta.sh` copies a public translator
    that calls a static helper even when the translator has a runtime form,
    a duplicate symbol at link; `$switched(?, ?)` with two anonymous holes
    never matches in a rule; a switch rule whose replacement holds a new
    `switch` recurses forever because the transform lowers the replacement
    twice (`rewrite-string-switch` depends on the second pass); a user
    `$rewrite($matched)` returning a quotation around `$node` does not see
    matches nested inside it.
- 2026-10-10, facts learned: `function-entry` placement is parse-time, so
  lambda cells need a transform-time entry placement before lambdas move; a
  plain `make build` after editing a shipped component leaves a degraded
  compiler (stale embedded prelude records, 9.2 G for the empty unit) until
  `make bootstrap-refresh`; the printf family table is spelled twice because
  the `.str()` warning reads it before the component runs.

## Next bounded milestone

1. Establish a complete declaration use case for initializer-only `$auto`.
   Compare a concrete implementation against the retained owner. Preserve mixed
   comma declarations, macro forwarding, constructed syntax, shared type identity,
   cleanup of the declared binding, exceptions, return aliases, and diagnostics.
   Keep prototypes and evidence outside tracked source until the boundary works.
2. Complete delegation using the same authoring principles. Preserve recursive
   lookup, ambiguity, precedence, and completion. Do not infer completeness from
   the wrapper example.
3. Review access, managed declarations, and delegation together. Measure total
   authored source cost and representative compiler translation/build workloads
   with the same toolchain, cache conditions, and job count. Keep synthetic
   measurements separate. Resolve demonstrated fixture failures before accepting
   the combined architecture.
4. Only then select further extraction, such as printf Var formats. Keep a
   feature in the kernel when extraction makes the whole implementation worse.

Do not add a second constructor API, renamed claim marker, feature-specific
emitter exception, or framework without concrete clients. Compare region
lowering separately rather than assuming a single producer requires a framework.

## Starting a fresh session

Use the directory and branch above. Read this plan, `AGENTS.md`,
`agents/README.md`, and the example README. Inspect `git status` and verify the
branch before editing. Use current source and recorded logs as evidence; no
previous chat is required. Other active repository plans are unrelated unless
this plan names them. Local commits are allowed; publication remains held.
