# Language component foundation

> Status: done, 2026-10-24.
> The foundation and selected component extractions are delivered on `dev`.
> The October 16 binding correction is `bcb22ae7a`; this closeout was
> checked against `7e9fd0178`.

## Closeout

Template free names resolve where the expansion lands. Only names listed
with `using name` retain a declaration from the author's file scope;
body-declared names remain private to each expansion. The October 12/13
author-binding default was superseded, as the decision below records.
The [language reference](../../docs/src/reference/language.md#hygiene-and-generated-names)
owns the current contract.

Compiler-inserted support calls remain outside program rules. Constructed
`with` uses ordinary language owners. The three residual research questions
are preserved in [review follow-ups](../reference/review-followups-2026-10-24.md#component-boundaries).
They do not keep the completed extraction campaign active.

## Historical decisions and delivery

The following status was recorded before this closeout:

> Historical status: active
> The foundation work is on `dev`; its working branch, started from dev
> `7e946b86663f9f069fe14e284c41e2aed73c57e0`, is history. Gary authorized
> publication to `dev` on 2026-10-09 after Milestone 0, the three component
> cases, `try`, and the driver work. This plan records what landed and owns
> the recorded decisions below.
> Updated 2026-10-14: the three recorded boundaries hold on `dev`. PR #193
> (`4d4c7aa9d`, 2026-10-13) delivered two of them. Shipped support calls
> stay away from program rules (fixture `rewrite-support-calls`). Template
> free names bind at the author's file scope (fixtures
> `macro-author-binding`, `macro-author-binding-scopes`, and
> `macro-forward-name-later-global`). The constructed `with` boundary needed
> no change: a `with` in a macro body behaves like the handwritten form
> (fixture `with-lexical`), and the
> [repository review](repository-review-2026-10-12.md#a-reproduced-defects)
> reproduced the `$!{}` quotation form with an uncommitted probe. No
> checked-in fixture covers the quotation form.

## Recorded decisions

Recorded with Gary on 2026-10-12. Selected component extraction is delivered;
the next work is limited to these existing language boundaries.

- Program rewrite rules see developer-written expressions, including `name`
  inside an interpolation hole. They must not intercept a compiler-inserted
  `String.join` support call merely because interpolation uses that call.
  A developer-written `String.join` call remains program code. Definitions of
  the program's own meta functions remain program code and reach function rules.
  Do not add origin authentication for canonical constructed Lists. The
  historical self-meta discrepancy is settled by
  [repository review decision 7](repository-review-2026-10-12.md#decisions-recorded-2026-10-12):
  a function rule rewrites the program's definitions, the copy the compiler
  runs is compiled as written, and no code change follows.
- Superseded 2026-10-16 by Gary: free names in a template resolve where the
  expansion lands, as decided on 2026-10-02 (a1feadd91, f6815d5e5). A
  template keeps a file-scope declaration only for a name it lists with
  `using name`. Names the body declares stay private to each expansion.
  The 2026-10-12/13 decision recorded here, that templates bind external
  names at the author's definition by default (33e1a21f5, #193), was
  reverted. Evidence: fixtures `macro-binding-landing`, `macro-author-binding`,
  and `macro-type-names-land`.
- A macro-constructed `with` form behaves like the same handwritten `with` form.
  Use the ordinary binding, placement, and lifecycle owners.

Do not start lexical defer or component interface/prelude packaging from this
plan. No current problem justified those proposals. Acquired-value cleanup is
already delivered. The later sections retain the extraction history; older
questions do not override these decisions.

## Goal and current boundary

Move language policy out of the compiler when ordinary component authoring makes
the complete implementation simpler. Use decorators, reusable macro patterns,
quotations, and Code/Type methods. Keep binding, typing, evaluation order,
statement placement, and lifecycle correctness with their existing owners.
Judge the entire authored change, including library and support code; a smaller
kernel alone is not proof of simplification.

The delivered log below records the current foundation: component lowering
for access, matching, literals, operators, lambdas, protocols, and Error forms,
plus ordinary managed-initializer placement. Those delivered decisions
supersede the initial recovery exclusions and milestone list preserved below.
Repository review decision 7 settled the self-meta function-rule observation
discrepancy without a code change; `docs/src/guide/meta-functions.md` states it.
The confirmed acquired-value cleanup repair is tracked in
[review remediation](../review-remediation-2026-10-11.md); the initial phrase
"cleanup of the declared binding" does not override that requirement.

## Initial recovery scope (historical)

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
[experiments](language-components-experiments.md),
[authoring](language-components-authoring.md), and
[kernel hypotheses](compiler-kernel-hypotheses.md).
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
(static `_slot_shape` in src/macros.x): a literal's value, an identifier
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
| destructuring | statement and declaration rules; delivered in wave 3 | 330 | few |
| string interpolation | literal `segments`; delivered in wave 2 | 200 | 730 |
| truthiness, getindex, dynamic operators | unary, binary, access; delivered in wave 1 | 410 | 620 |
| lambda lowering | lambda rules; unit-support and function-entry placements; delivered in wave 5 | 1,500 | 586 |
| protocols: adapter synthesis only, per `plans/archive/protocols-component.md` | `conform` node rule; unit-support and unit-init placements; delivered in wave 6 | 300 | 153 |
| match, per `plans/archive/match-component.md` | `match` statement rule; delivered in wave 2 | 340 | 407 in src |

Runtime static locals and class defaults stay in the kernel; the log of
2026-10-10 records why. `match` joined the table after
`plans/archive/match-component.md` was accepted.

Kernel deletions no feature blocks: none remain; the `function-entry`
placement now works at transform time for lambdas, and destructuring needed
no placement. The wave 2 audit found no deletable `Compiler` field
and no per-call Lisp session setup left in the driver; the prepared
replacement template and fill steps are the remaining driver cost.

### Open, needing research before a decision

Note added 2026-10-14: this list now holds only open items. The earlier
items are settled. `match` was delivered in wave 2. The template binding
rule was decided 2026-10-12 and delivered in PR #193. Conformance was
delivered in wave 6 and then recorded across interfaces. Constructed `with`
already behaves like the handwritten form. The recorded decisions withdraw
lexical `defer` and the linked prelude's packaging. Rewriting the kernel's
hand-built lowerings as quotations is not selected work.

- Constructed `with` in a quotation: the macro-body form is covered by
  fixture `with-lexical`, but the `$!{}` quotation form was checked only by
  the repository review's uncommitted probe at `2ec6ea71`.
- Shipped components and the meta builders: on 2026-10-10 a component could
  not call `lib/meta.x` builders without failing its linked-copy check in
  meta builds. `feddf6913` later resolved shipped rule and template names
  through the linked copies; the builder case was not rechecked.
- A prelude component rule lost during collection is still silent at
  collection (see the wave 2 log entry).

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
- 2026-10-10, raise simplified: `component-raise.x` went from 97 lines to 61.
  The static check keeps the flat type test and drops the walk over List
  contents and `*_var` boxing calls, which repeated the runtime's `_copy_value`
  check (now static in lib/error.x) at the `<bad-types>` floor. The book now
  says a value's own invalid type is a compiler error and invalid contents of a
  List or Var value reach the floor when the raise runs; the
  `raise-invalid-nested` fixture is gone, and a probe confirmed the floor
  message for its program.
- 2026-10-10, match research (`plans/archive/match-component.md`, branch
  `kernel/match-research`): a match component is feasible at 4.75 M per use
  against 4.62 M for the kernel arm on a three-arm workload, with runtime
  3.6-10x faster than the plan cache, deleting about 334 kernel lines. It
  needs a documented verbatim-C-text emitter rule, `Code.pattern_value`,
  `x2c_fresh_binding`, match as a rewrite point, and lowered results that
  skip the prepared walk.
- 2026-10-10, wave 2 (held for review on `kernel/wave2-integration`): three
  workers from 9805f3c2, integrated as one batch.
  - `match` is `src/component-match.x` per `plans/archive/match-component.md`, in
    two moves. Move 1 ports the emitter: kernel -340 (emit.x match section
    and templates, transform.x `_match_cases`/`_match_records`/`matchcases`,
    compiler.x flat-pattern helpers, cleanup.x `matchcases`), shared
    services +38, component 266 lines, net -30. Move 2 tests static
    patterns in place with nested `if` tests: component 392 lines, +126
    against the plan's estimate of about 65; the extra is explicit pending
    stacks instead of recursion, rollback when a pattern leaves the nested
    subset, and declaring cursors and the buffer only when used. The one
    SDK addition is `Code.pattern_value`; the plan's fresh-binding
    operation was not needed because the `_x2c_gensym_match_*` names are scoped to
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
- 2026-10-10, wave 3 (held for review on `kernel/wave3-integration`):
  destructuring is `src/component-destructuring.x`, 127 lines, three rules
  (declarations of both forms, the assignment statement, the assignment
  expression) returning hand-built `(code-value "bound" CODE ROWS)`
  carriers with `new-name` rows, so the parser-declared targets keep their
  scope and the temporaries keep the kernel's names. The kernel lost 188
  lines and gained 53 (net -135): `_destructure_*`, `_named_destructure`,
  `_typed_destructure`, `_as_statement`, three template macros, and
  `$report.type.destructure_list`; parsing and its diagnostics stay. The
  lambda-cell pre-pass stays and now runs only for bodies that contain a
  lambda. No SDK operation and no placement were added; the assignment
  expression registers at the `literal` point keyed `dstrasgn` and the
  statement at `node` keyed `stmnt`. Generated C is byte-identical to the
  baseline for every fixture and the compiler's sources. Workload of 1000
  three-name declarations: 5.84 G -> 5.36 G (-8.1%); empty unit and
  self-translation within noise. Two fixtures added: `lambda-destructure-
  cell` (the pre-pass had no coverage) and `rewrite-destructuring` (user
  rules on all three heads). Open: a user `dstrdecl` rule whose replacement
  holds `$node` applies twice in a lambda body, the same family as the
  switch re-lowering defect; binding a declaration of a parser-bound name at
  transform time leaks it to later resolution across functions; prelude
  component macro names are global and can collide with user meta names;
  `tools/gen-linked-meta.sh` counts `$type (` inside a quotation as a call.
- 2026-10-10, transform-time function-entry placement (`kernel/entry-
  placement`): a `$rewrite` rule running while the transform lowers a
  function body can call `x2c_place(%(function-entry), code)`. The frame is
  the parser's own `Ancestor` row, pushed by `Compiler.enter_function` and
  delivered by `leave_function`, which binds the placed code in a new scope
  with the function's result type; `_function_node` lowers it with
  `_sequence` ahead of the body's first statement. A captured lambda's body
  gets its own frame in `CaptureBuild.publish`; a non-capturing lambda is a
  lifted function already. A transform-time placement from inside a lambda
  body lands at the entry of the lambda's own function. `x2c_enclosing
  (<function>)` now answers at transform time. A carrier's `(place WHERE
  CODE)` row has earlier `new-name` tokens replaced in CODE. +149/-26
  authored, byte-identical C, fixture `rewrite-function-entry`. Open: a
  rule inside a `defer` finalizer at transform time is unchecked; code
  placed at transform time that places again finds no frame.
- 2026-10-10, rule driver defects fixed (`kernel/rule-defects`): a switch
  replacement lowers once through `_watched` with its held parts, so a rule
  returning a new `switch` terminates and a nested match in a braced arm
  reaches a `$node`-wrapping rule; anonymous `?` and `*` holes in a
  macro-valued pattern match as wildcards (the binder stand-in
  `__macro_anonymous` survives the view that quotes bare operators); a
  statement replacement bound without lowering gives its own statements of
  the rule's kind to the later rules at once (`_bound_held`), which also
  fixed lambda cells never seeing a destructured target (a captured target
  read garbage) and a user `try` rule crashing the compiler;
  `tools/gen-linked-meta.sh` blanks comments, strings, quotation data, and
  `%()` lists before counting calls and copies only functions that reach a
  compiler prototype. +172/-37 authored in src, lib, and the tool; four new
  fixtures. Empty unit +0.5%, within spread. Open: a user switch rule is
  offered the switch the match component emits, and a replacement around it
  fails because the body holds verbatim C text; an unbraced nested statement
  that changes when rebound is not re-offered; `c.return_type` is NULL during
  transform, so a rebound `return` in a statement replacement loses its
  declared type and conversion.
- 2026-10-10, wave 5, lambdas (held for review on `kernel/wave5-
  integration`): lambda lowering is `src/component-lambdas.x`, 493 lines,
  in three moves: the lift of non-capturing lambdas to wrapper functions
  through a `unit-support` placement; capturing lambdas as a lifted
  function plus an adapter that calls it, with the kernel lowering in
  `callables.x` deleted; and the cells, registered in two steps because a
  function rule fires on every function in every unit that sees the
  component, so the seed must link `lambda_cells` before it is matched.
  Kernel -616/+130 (net -486), component +493, total +7; without the shared
  services the move is -49. One SDK operation, `Code.func_parameters`,
  returns the signature and reader rows the adapter needs; the `lambda`
  head joins `Code.register_rewrite` and `x2c_enclosing(<statement>)`
  answers while lowering. Kept in the kernel: parsing, capture resolution
  and checks, lambda typing, region checks, `Compiler.lambda_scopes`.
  `Func` conversions and typed callbacks stay because they also serve
  native functions. Translation per lambda: non-capturing 7.86 M -> 7.56 M;
  value capture 9.78 M -> 13.44 M (+37%); reference capture 12.18 M ->
  18.31 M (+50%), mostly binding the adapter and the placed definitions;
  the 500-function lambda workload 20.72 G -> 26.46 G; self-translation of
  expressions.x within noise. Runtime per call: non-capturing unchanged;
  captures +11 to +13 instructions for the adapter's call into the lifted
  function. Generated C changes for capturing lambdas only (new shape,
  fields `c0..`, one conversion per captured value per call); six
  expectation files and three transform dumps changed. Fixed in passing: a
  lowering-time diagnostic inside a lambda expression body now reports at
  the lambda's statement. Follow-ups that recover the capture cost: a
  hand-built adapter, and cell declarations built without rebinding;
  `watched_step` scans every source expression once per lowering step, so
  a large lambda body costs quadratically.
- 2026-10-11, wave 6, protocol adapters (`kernel/protocols-component`, move 1
  of `plans/archive/protocols-component.md`): adapter synthesis is
  `src/component-protocols.x`, 199 lines, a rule on the `conform` form
  `(conform BASE PARTICIPANT FORWARD REVERSE BINDER DESCRIPTOR (ROW...))` that
  the kernel presents for each resolved conformance whose forward converter the
  unit defines; rows carry bound names so generated members keep their method
  display, and static `_generated_support` in src/protocol.x keeps a documented
  prototype's prose. The component writes forwarding members, descriptor
  thunks, method tables, and registration through unit-support and unit-init
  placements; `Compiler.shipped_support` binds a rule's result into the unit's
  support and reports `no rule lowers this protocol conformance` when none
  answers. Kernel -259/+109 (net -150): the `AdapterFunction` and
  `ProtocolAdapters` generation, the render guard, descriptor registration and
  its helpers. No SDK operation; the `conform` head joins
  `Code.register_rewrite`. Generated C byte-identical for the plan's workloads,
  lib/common.x, and every fixture. Cost: +1.28 M per conformance (W1 minus W0:
  11.1 M -> 13.7 M per type with two conformances) against the plan's +1.0 M;
  member resolution per use unchanged; lib/common.x +76 M (+1.9%);
  src/protocol.x -416 M. Sampling puts the cost in `bind_syntax` under
  `Compiler.place`, about 30% of it landing and thawing quotations. Fixtures:
  `rewrite-conform` (a user rule on the head) and `protocol-documented-member`,
  with a new `definitions` fixture phase that runs `--dump-definitions`.
- 2026-10-11, three rule-driver defects fixed (`kernel/rule-defects-2`):
  a statement that a shipped rule's lowered carrier writes is not source,
  so only shipped rules see it (`SlotWatch.shipped`; the match component's
  emitted `switch` no longer reaches user switch rules, while held arm
  bodies still do); binding that rebuilds a watched unbraced statement
  tells the active watch (`Compiler.rebound` from `_bind_statement`), so a
  `$node`-wrapping rule reaches an unbraced arm, `if`, or `while` body;
  `_entered_body` binds `c.return_type` to the declared result while a
  function body lowers, so a rebound `return` keeps its conversion. +40/-12
  in src; three fixtures; self-translation of expressions.x -2.6%, cause
  unknown. Open: a `return` inside a try body breaks a `$node`-wrapping
  `$tried` rule (the try rule runs in the cleanup walk after the return is
  lowered); `c.return_type` is still NULL in the cleanup walk's
  `_landing_form`.
- 2026-10-11, try-body return fixed (`kernel/try-return`): the try rule
  runs in the cleanup walk after the body has lowered, so a program rule's
  replacement around `$node` rebound lowered syntax (`(return EXPR)` with no
  type slot, and likewise a lowered `defer` or `match`) and failed with
  "syntax cannot be constructed at this position". `_landing_form` now calls
  `Compiler.rewrite_lowered`, which wraps the source and its held parts as
  lowered carriers before a program's replacement binds, and
  `Compiler.lower_replacement` lowers the replacement under a `kept` watch
  so those parts are not lowered again; this also stopped user `raise` and
  `switch` rules applying twice inside try bodies. `_lower_function` binds
  `c.return_type` around the cleanup walk; `Walk.return_type` is gone.
  `Ast.replace_nodes` in ast.x replaces nodes by address without recursing
  and replaces cleanup.x's private copies. +120/-68 in src; fixtures
  `rewrite-try-return` and `rewrite-try-held-statements`. Open: a program
  `$tried` rule also receives the compiler-written `try` that
  `lower_defer_region` emits for a defer whose finalizer returns.
- 2026-10-11, recorded conformance (`kernel/recorded-conformance`, Gary's
  decision after the two-unit divergence was explained): the declaring
  unit records each ordinary external conformance in its `.xi` as
  `("source-node" (conformance BASE PARTICIPANT))` -> `(conformance BASE
  PARTICIPANT FORWARD REVERSE (bindings (NAME TYPE)...) (MEMBER STATUS
  SOURCE)...)`, 85 rows and 27.7 KB across lib and src (+1.1% interface
  bytes); an including unit installs the row lazily on first use and skips
  resolving that adoption; own, static, and native adoptions behave as
  before; a cold walk of the declaring unit still resolves locally. A member
  implemented by a function static to the declaring unit is recorded as
  `no-member`, since no other unit can call it. +196/-22 authored in
  protocol.x and collect.x. Generated C byte-identical for lib, src, and
  every fixture except the new divergence fixture, whose including unit now
  agrees with the declaring unit. Equivalence check: 4,747 reuses in lib and
  src and 42,854 in fixtures, one difference (the intended fixture). Cost:
  empty unit -15.8 M (-1.3%) against the plan's -38 M, because rebuilding
  the expected types and parsing the rows costs about as much as resolving;
  the declaring unit pays about 0.2 M per recorded conformance (W1 +1.1%);
  lib/common.x -0.6%. Follow-up the same day: the first gate failed in
  `protocol-generated-owner-precedence-swapped`, a one-unit probe, because
  the lazy install inserted into `c.conforms` while
  `install_generated_protocol_symbols` iterated it (a Map traversal is
  invalid after structural mutation, and List keys hash by address, so the
  skip depended on layout; 8 failures in 150 serial runs); the loops that
  can insert now iterate a snapshot. The cold path also agrees with the
  interface: when collection walks a file that declares external
  adoptions, a separate compiler resolves them in that file's own view
  (prelude plus include closure) at the end of `collect_symbols` and writes
  the same rows into the process-cache entry, so an including unit's answer
  no longer depends on whether the declaring unit's `.xi` was current. A
  file that imports a package records nothing in either path. Cost of the
  cold path: about 0.8 M per adoption the walked file declares (+314 M when
  a 400-adoption header is walked cold; +41 M on the empty unit with
  `--no-interfaces`); the warm empty unit is -26 M. Fixture
  `protocol-recorded-conformance-cold` forces the cold path. Authored total
  for the change: about +400 lines in collect.x and protocol.x.
- 2026-10-11, defer landing try hidden from program rules
  (`kernel/defer-try`): `lower_defer_region` and the unsupported-capture
  path of `_callable_defer` write `(try BODY () FINALIZER kernel)` through
  `_landing_region`; `_landing_form` strips the mark and lowers it through
  `Compiler.rewrite_written`, which binds a `shipped` watch so only shipped
  rules see it. Statements the kernel writes while lowering are not source
  and reach only shipped rules, now stated in agents/lowering-with-
  macros.md. +36/-10 in src; fixture `rewrite-try-defer-landing` (program
  try count 9 -> 2). Open: a program function rule is offered the defer
  callback `_x2c_gensym_defer_cleanup_N` that `_callable_defer` writes, and
  lambda-lifted functions raise the same question for kernel-written
  definitions.
- 2026-10-11, lambda long-function gap (`kernel/lambda-gap`): the cells
  rule keeps each run of unchanged function items as one lowered `(seq)`
  carrier instead of one carrier per item, takes the rebuilt items as an
  Array, and compares by identity; `_replace_bindings` tests only atoms as
  binders and lists through `Ast.try_binding`. The 60-statement
  shared-local shape went 13.57 M -> 11.95 M per lambda against the kernel's
  11.59 M fresh (11.75 M in the plan); every other shape is at or below the
  kernel; functions without lambdas unchanged; C byte-identical. The last
  0.3 M is the mention walk; recording mentions in the shared walk recovered
  it but cost every lambda-free 60-statement function +0.35 M, so it was not
  taken. +33/-17 authored.
- 2026-10-11, written definitions reach only shipped function rules
  (`kernel/generated-definitions`): a definition the kernel or a shipped
  rule writes (defer callbacks, lifted lambdas and adapters, protocol
  forwarding members and thunks, a shipped rule's replacement of a
  definition) carries the `kernel` mark, `(function RT DECL BODY kernel)`,
  added by `Ast.written_definitions` on `Compiler.add_early` and by
  `Compiler.written_support` when the applying rule is builtin; `_step`
  strips it and `_function_rewrite` dispatches under a `shipped` watch,
  which `_rewrite` now honors at the function point. A program rule's own
  `unit-support` placement and a program `conform` rule's result stay
  program code; the body of a written definition is still source for
  statement rules. `Compiler.applying` names the rule whose meta function is
  running, because the protocol component places support while its function
  runs, before the rule is in `active_rewrites`. +88/-21 in src; fixture
  `rewrite-function-written` (offered definitions 10 -> the program's).
  A `*written` capture in `_step`'s match enlarged the transform's frame and
  failed `var-chain-stack` at 256 KB; a capture-free case fixed it. Open: the
  `(early KEY BINDING DECL)` carrier effect has no producer and still goes
  through `add_early`; a program function rule is offered its own meta
  function in one case and not others, predating this change.
- 2026-10-11, three cleanups (`kernel/trio`): the `early` carrier effect is
  deleted with its only producer, the `macro-early` fixture (the
  `unit-support KEY` placement does its job); the book states that a meta
  function's runtime form is one of the program's definitions, so a function
  rule receives it; `_function` in builtins.x spells `(void)` for a default
  class method without parameters, so generated headers carry prototypes
  (`Box_alloc(void)`, `SourceView_new(void)`) and `--live-symbols` accepts
  them. `make proof-conformance` still fails on an older defect: the host
  preprocessor runs with `-I include/x2c`, so `#include <string.h>` in
  lib/common.x resolves to the generated `include/x2c/string.h` when
  lib/x2c.x is preprocessed without `-imacros lib/x2c.x`, and var.h's TagId
  enum collides with var.x's. Every other unit agrees between prelude and
  live-symbol modes (141 units).
- 2026-10-11, host preprocessor search order (`kernel/include-shadow`): in
  the `--cpp-symbols`, `--live-symbols`, and `--dump-cpp` modes the default
  include directory `<root>/include/x2c` was passed as `-I`, so an
  angle-bracket `<string.h>` resolved to the generated runtime header and
  pulled var.h's `TagId` enum into lib/x2c.x. The default directories now go
  as `-idirafter`, after the system directories; user `-I` directories are
  unchanged, and every runtime-header include in the corpus is quoted.
  Ordinary translation never runs the host preprocessor, so generated C is
  unchanged. +20/-15 in toolchain.x, frontend.x, utils.x. `make
  proof-conformance` still fails on lib/x2c.x: the cpp-mode shallow parse
  skips unit macros (`collect_protocols = 0` in `_tokenize_cpp`), so a static
  type a unit macro creates in an included file (`ErrorRegion` from
  `$error.private.types()`) is unknown and lib/error.x fails to parse; past
  that, `$(defun native.scalar.list ...)` fails compile-time Lisp evaluation
  in lib/x2c.x only. The prelude has failed in the cpp modes at every
  revision checked; it owns no conformance rows.
- 2026-10-11, the prelude leaves the cpp-mode proofs (Gary's decision):
  `tools/check-conformance-coherence` and the raw-symbol sweep skip
  lib/x2c.x. The live and cpp symbol modes check a unit against the
  prelude's symbols, so checking the prelude against itself has no meaning;
  it owns no conformance rows; and its cpp-mode parse does not expand the
  unit macros its included files rely on (a static `ErrorRegion` from
  `$error.private.types()` is unknown, and a `$(defun ...)` from
  native-scalar-types.x fails compile-time Lisp evaluation in that unit).
  Fixing that chain would change what the cpp-mode shallow parse collects
  for every unit; it is recorded here as the known gap instead.
- 2026-10-11, `make proof-raw-symbols` passes (`kernel/raw-sweep`): the
  cpp-mode shallow parse bound no `meta` stubs for included definitions
  (`install_collected_meta_function` returned at once when `source_private <
  0`), so an included file's own `$thirty()` found no binding and a shadowing
  unit's `$forty()` reached the wrong helper table; the new static
  `_install_included_meta` in src/meta-native.x binds a public included
  definition through `install_project_meta_effect` with its file as provider,
  and the unit's own and static definitions take the ordinary path. The sweep
  now follows quoted includes from every fixture and classifies a companion
  that only negative fixtures include as not expected to translate (four
  companions that failed and two that happened to pass). The probe
  `source-call-projection.x` called `$source_pattern`, removed 2026-10-02, and
  nothing ran it; deleted. +20/-1 in meta-native.x, +33 in the sweep. Proofs:
  raw-symbols 0 failures of 927 required, conformance 141 units,
  cold-collection 426 files. The remaining cpp-mode gap is the prelude's unit
  macros, recorded above.
- 2026-10-10, facts learned: `function-entry` placement is parse-time, so
  lambda cells need a transform-time entry placement before lambdas move; a
  plain `make build` after editing a shipped component leaves a degraded
  compiler (stale embedded prelude records, 9.2 G for the empty unit, about
  twelve dump fixtures differing) until `make bootstrap-refresh`, and a
  timestamp change alone, with content equal to the bootstrap's, or a plain
  `make build` after `make bootstrap-refresh`, does the same until
  `make build-safe`; the printf family table is spelled twice because
  the `.str()` warning reads it before the component runs.
- 2026-10-11, lambda cost recovery (`kernel/lambda-cost`, held for
  review): the adapter and the context record are bound carriers, so they
  are not bound again; their fields and the adapter's locals keep their
  spellings and bind no name, which also fixes a file-scope `c0` colliding
  with a record field. A lambda body is rebuilt only when it holds a bare
  return. Carrier token replacement copies only the lists it changes. The
  cell rule keeps the statements that hold no cell as they are bound, binds
  only the cells and the statements around them, and builds each cell's
  allocation as a typed quotation; a nested carrier is searched for
  leftover binders only where it is taken. Translation per lambda, kernel
  -> component -> now: non-capturing 7.61 -> 7.37 -> 7.22 M; value capture
  8.87 -> 12.87 -> 8.60 M; reference capture 9.69 -> 13.86 -> 9.65 M; a
  60-statement lambda body 28.40 -> 37.35 -> 19.34 M; a 60-statement
  function whose lambda shares a local 11.75 -> 45.53 -> 13.57 M; the
  500-function workload with one of each kind 18.19 -> 22.27 -> 17.99 G.
  Generated C is unchanged for the compiler's sources and for every
  fixture except two: `local-typedef-constructed` numbers its local
  typedefs lower and `rewrite-function` loses a redundant block, because a
  function with cells is no longer bound twice. Not changed: the slot watch
  scan is linear per step and measured under 1% on every lambda, try, and
  match shape tried, with no quadratic growth; the adapter keeps calling
  the lifted function, which costs about 12 to 18 instructions per captured
  call at `-O0` and none at `-O2`, where the C compiler inlines it, and moving
  the body into the adapter would place function-entry code ahead of the
  lambda's parameters.
- 2026-10-14, open items closed: every earlier "Open:" item in this log is
  closed on `dev` except the silent loss of a prelude component rule at
  collection, recorded in the wave 2 entry. The closing commits are
  `bff20a02f`, `94bd9f200`, `fac2d421a`, `9312cb627`, `f0e50bbe9`,
  `963eb2d24`, `049d254ee`, `863f166ab`, `feddf6913`, `5b81dec4f`,
  `2c6f501a7`, `4c8be46d1`, `01856950d`, `79d5bed9c`, `f64e9c292`,
  `30810f69c`, `1d7779357`, `26fcdf263`, and `ed35a035d`, dated 2026-10-10
  through 2026-10-12.

## Initial milestone sequence (superseded by the delivered log)

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

Start from current `origin/dev` and read the delivered log before selecting
remaining work. The old branch and recovery exclusions record historical
scope. Root `AGENTS.md` owns current delivery, and a new task instruction owns
its implementation scope. Do not repeat delivered extraction milestones or
treat their historical publication hold as current authorization.
