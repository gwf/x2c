# Remaining review follow-ups

> Status: active - follow-up ownership, recorded 2026-10-31 at `2b7a2b422`.
> The confirmed repair batch has its [own record](archive/recent-wave-repairs-2026-10-31.md).
> This plan owns the residual implementation questions below. Recording an
> owner does not authorize every candidate's implementation or a new gate.

## Remaining work

Each row names its source owner and the next bounded action. The October 30
[repair archive](archive/review-remediation-2026-10-30.md) retains the original
observations. Source inspection supported these rows on October 31; they were
not all reproduced as executable failures.

| ID | Follow-up and source owner | Next action |
| --- | --- | --- |
| F1 | Script LSP cursor offsets: `src/collect/walk.x`, `src/compiler/source-locations.x`, `commands/lsp/analysis.x`. Rewritten script text and raw editor text can use different offsets when no unit is open. | Reproduce one cursor request on a closed script, then use the existing source-location mapping to preserve the original position. |
| F2 | Optional native-module probe: `unittest/probes/run-native-modules.sh`. Its REPL check submits a `meta` declaration, which the native playground rejects. | Reproduce the optional check and replace that submission with the supported source-load workflow. Preserve compile-time native-module coverage separately. |
| F3 | Lint member documentation tiers: `commands/lint/comments.x`. Exact manifest-path lookup does not give a module member its entry's tier. | Add a focused member example, then reuse the entry's existing manifest tier. Keep lint optional and experimental. |
| F4 | Included-header attribute macros: `src/parse/types.x` and `src/collect/`. A macro from an included `.h` used before a unit declaration was reported to fail parsing. The adjacent written-source case, an attribute macro before `typedef` dropping its attribute, is repaired by batch A3 of the [margin repairs](archive/review-repairs-2026-11-01.md). | Reduce and reproduce the included-header case on its own. Trace existing modifier collection before proposing a repair. |
| F5 | Linux REPL shared-library identities: `commands/repl/repl-program.x`. Decorated GNU ld trace lines are treated as whole paths. | Reproduce `-lfoo (path)` output on Linux and check whether changing that library invalidates the session artifact. Reuse the current dependency identity path. |
| F6 | CPP signed arithmetic: `src/cpp/conditions.x`. Addition, subtraction, multiplication, and unary negation still use native signed `long` operations. | Reproduce overflow with the existing sanitizer tooling and establish the documented preprocessing arithmetic contract before changing results. |
| F7 | HTTP releases example: `examples/packages/http-json-releases/`. Its default GitHub endpoint does not establish support for the fixture server's `/summary` POST. | Use a local fixture to verify the example's intended flow, then correct the documented/default endpoint behavior. Do not send a live POST merely to investigate. |
| F8 | Notes database-thread instructions: `examples/apps/notes/bench/database-thread.md`. The documented build still supplies redundant include flags. | Check the ordinary package/source discovery path and remove only arguments it already supplies. |
| F9 | Documentation gate scope: `tools/gate-state.py` and `tools/integrate-dev.py`. A fresh integrator candidate has no evidence record, so doc-check runs all runnable documentation samples. | Trace the existing PR-range data and determine whether passing that range can reuse the current changed-document check without weakening it. Do not add validation or a recurring requirement. |

The main-checkout hook update and the packaged VSIX changelog are resolved.
They are not pending rows. F10, local definitions under Macro-target
decorators (A6 of the [margin repairs](archive/review-repairs-2026-11-01.md)),
closed on 2026-11-01 without a compiler change: the local is published and
visible, and the reported `guard() { ... }` failed because a local decorator
with no explicit parameters is spelled bare, `guard { ... }`, as
`macro-local` already covers. `macro-decorator-continuation` now holds the
function-scope case with one and two Macro-target decorators, and the book's
"Local definitions" names the spelling. The site `compile-time-lisp` fragment remains an
intentional compatibility choice, not an omitted rename.

## Other owners

- [Language-reference writing](review-remediation-2026-10-11.md) owns the
  remaining rewrite explanation and runtime Lisp truthiness/host-limit text.
  Binding explanations and the AST catalog already exist.
- [Structured lint findings](x2c-lint-and-format.md) owns the approved optional
  List output and compiler consumer. F3 above owns the separate existing-rule gap.
- [Detached Channel ownership](detached-channel-ownership.md) owns recovery of
  the historical benchmark and delivery-hold decision, not more implementation.
- [Deferred language and library candidates](reference/deferred-candidates-2026-10-31.md)
  owns conditional JSON/assertion, Array rest, meta Map, quotation, and browser work.
- [Async performance](reference/async-performance-followup-2026-10-31.md)
  owns the explicitly deferred normal benchmarks and recorded evidence limits.
- [Benchmark website integration](../site/BENCHMARKS.md) owns the future page
  and its saved-data requirements. No page or deployment is selected here.

## Plan review

These rows preserve existing source, lifetime, visibility, and distribution
contracts. They add no runtime representation, validator, diagnostic, test
target, or recurring process. Each future repair starts with its named
reproduction and reuses its existing owner. The current six confirmed fixes
are tracked separately from these uncompleted follow-ups.
