# Repairs at the margins of the recent PR wave

> Status: done - implemented and validated 2026-10-31.
> Source repairs through `613c8c6e8`; publication validation at `a24584652`.
> Archived after the combined gate and focused performance checkpoint.
> Final archive bookkeeping follows the same dev delivery batch.
> Baseline: `2b7a2b422cf4987f7dcba5da834bca30661afe31`.
> Scope: six confirmed review gaps, follow-up ownership, and completed-plan
> archival. Remaining candidates have a [separate owner](../review-followups-2026-10-31.md).
> Expensive validation follows implementation and combined source review.

## Selected repairs

| Repair | Existing owner and intended result | Focused evidence |
| --- | --- | --- |
| Pattern-condition false continuation | `src/transform/conditions.x`: place an `else if` continuation inside a block so generated C preserves its branch without dangling-else warnings. | Execute the chain with true/false arms and strict native warnings. |
| Leading typedef attributes | `src/parse/declarations.x` and `src/parse/types.x`: recognize typedef storage together with attributes and retain ordinary typedef name binding and layout facts. | Compile a leading unused/alignment typedef example and check the resulting type. |
| Quoted keyword atoms under CPP | `src/cpp/`: distinguish keyword tokens in source from keyword spellings stored as literal atoms, using the tokenizer's existing kinds. | A visible keyword macro must still expand source while leaving quoted atom data intact. |
| Syntax generator script helpers | `commands/build/`: include the syntax tool's real source helpers without collecting unrelated compiler runtime assets as script helpers. | Build/run the generator from the checkout and retain command helper-discovery checks. |
| Scope example migration | Current site examples and agent guide: use the current package examples and Scope operations. | Inspect excerpts and run the relevant small native samples without fetching third-party packages. |
| Generated protocol-owner diagnostic | Existing protocol signature resolution and report: reject the incompatible generated owner at its adoption with expected/actual signatures. | Existing conflict fixture and related owner-precedence fixtures. |

## Closeout and delivery

Archive completed async, spike, derive/test, Map-rest, quotation, browser, and
networking records without discarding their evidence. Move conditional work
into its explicit reference owner. Keep active lint, language writing, and
detached-ownership evidence closeout. Preserve the deferred async benchmarks.

Review the combined authored diff before broad validation. Run focused checks,
the applicable existing performance checkpoint at the end, then the existing
publication gate once for the coherent batch. Delivery is direct to dev.
Generated bootstrap and documentation remain owned by their existing targets.

## Delivered result and verification

All six repairs are implemented. The syntax tool also passes its dedented
usage text as a printf argument, eliminating its native format-security
warning. No public API, ownership boundary, or supported target changed.
Seven previously completed plans are archived with their residual work moved
to the named owners. The stale test-command promotion action is closed.

Validation was deferred until the combined authored diff was reviewed:

- `make stage-1` and focused fixtures for attributed typedefs, quoted CPP
  keywords, pattern-condition branches, and generated-owner conflicts pass.
- The strict dangling-else probe compiles and prints `3`. The conflict fixture
  reports the incompatible generated signature at `protocol Var(Item)`.
- `x2c script tools/syntax-spec summary` runs from the checkout;
  `x2c script tools/syntax-spec check` reports zero stale outputs.
- `tools/gate-state.py ensure agent-pr-check`, through `tools/land-dev`,
  passes: 1,158 unit tests, 99,597 assertions, 1,380 compiler fixtures and
  3,046 artifacts, self-host comparisons, 479 cold-collection files,
  documentation audit, 138 runnable documentation samples, and command checks.
- The first attempt exposed the intentional `match-condition.c` brace change
  and one continuation-indent violation. Both were corrected without changing
  the linter baseline. Full failure logs remain in
  `debug/recent-wave-first-gate-checks/` and the original land-dev logs.

The macOS arm64 compiler checkpoint compares `2b7a2b422` with `a24584652`.
It translates the existing seven representative units from each respective
source tree: transform, emit, expressions, generate, parse, type, and tokenizer.
Five alternating samples follow one warmup per compiler. Both compilers have
complete default preludes. Each source has a separate output directory and
runs from its own checkout to avoid cross-home/interface collisions.

Median aggregate instructions are 56,492,594,154 before and 56,501,003,355
after (+0.015%). Median elapsed time is 3.605 s before and 3.617 s after.
These are this partial translation workload's observations, including its
small source-corpus change; they are not an isolated translator-cost estimate
or evidence of a general speed improvement/regression. Raw samples and exact
revisions are in `debug/recent-wave-performance-isolated/results.json`.
Preliminary cross-home/shared-output attempts failed and are excluded.

Normal async benchmarks remain deferred. No new cross-platform sanitizer,
third-party package, website deployment, or headed-browser campaign ran.
Those claims are outside this repair batch's evidence.

## Plan review

Canonical AST structure, ordinary type binding, protocol signature unification,
token kinds, and script helper boundaries remain authoritative. Repairs reuse
those owners rather than adding a second parser, validator, state registry,
ownership mechanism, or public API. The conflict report and focused negative
fixture protect an existing incompatible signature contract. Other regressions
exercise wrong emitted C, literal corruption, and broken helper discovery.
No new recurring gate, test target, or process requirement is introduced.
