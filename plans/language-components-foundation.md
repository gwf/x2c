# Language component foundation

> Status: active
> Local recovery branch `codex/language-components-foundation`, based on dev
> `7e946b86663f9f069fe14e284c41e2aed73c57e0`. No push or dev/main integration.
> Working directory: `/Users/gary/.codex/worktrees/language-components-foundation/x2c`.
> This file alone owns continuation of this branch's component work.

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
