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
