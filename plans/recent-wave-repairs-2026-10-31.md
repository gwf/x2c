# Repairs at the margins of the recent PR wave

> Status: active - implementation authorized 2026-10-31.
> Baseline: `2b7a2b422cf4987f7dcba5da834bca30661afe31`.
> Scope: six confirmed review gaps, follow-up ownership, and completed-plan
> archival. Remaining candidates have a [separate owner](review-followups-2026-10-31.md).
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

## Plan review

Canonical AST structure, ordinary type binding, protocol signature unification,
token kinds, and script helper boundaries remain authoritative. Repairs reuse
those owners rather than adding a second parser, validator, state registry,
ownership mechanism, or public API. The conflict report and focused negative
fixture protect an existing incompatible signature contract. Other regressions
exercise wrong emitted C, literal corruption, and broken helper discovery.
No new recurring gate, test target, or process requirement is introduced.
