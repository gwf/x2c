# Deferred language and library candidates

> Status: reference, 2026-10-31. These candidates survived completed plans.
> None is selected for implementation by this closeout. Each row has one
> owner here and a concrete trigger; its archive retains historical evidence.

| ID | Candidate | Trigger and boundary | Delivered record |
| --- | --- | --- | --- |
| C1 | Derived JSON round trips for Symbol and List fields | Establish a caller that needs tag-preserving round trips, then decide encoding and compatibility. Existing JSON loses those tags; Map and row mappings preserve them. | [Derive and test](../archive/derive-and-test.md) |
| C2 | Shared user/repository assertions | Assess duplication when `test.x` usage demonstrates a useful shared implementation. Preserve repository Scope-balance rules and both harness contracts. `x2c test` already shipped in PR #626. | [Derive and test](../archive/derive-and-test.md) |
| C3 | Array rest parameters | Wait for a caller needing indexed tail access. Decide ordinary Array literal splicing before introducing a rest-only packing path. | [Map rest delivery](../archive/map-and-array-rest-parameters.md) |
| C4 | Meta-produced Maps as meta arguments and rest splices | Reproduce a useful caller blocked by the existing cross-stage Map limitation. Settle the ordinary meta Map value boundary before extending Map rest. No support is claimed by the completed runtime Map-rest work. | [Map rest delivery](../archive/map-and-array-rest-parameters.md) |
| C5 | Individual quotation adoption | Select one demonstrated simplification that preserves binding, canonical Lists, staging, timing, and ownership. Historical census counts commission no blanket rewrite. | [Quotation closeout](../archive/quotation-adoption-closeout-2026-10-31.md) |
| C6 | Generate TagId from its rows | Compare `lib/var/var.x` and `lib/var-tags.x`; preserve every ID and name without imposing meta dependencies on ordinary Var users. This remains lower priority. | [Quotation closeout](../archive/quotation-adoption-closeout-2026-10-31.md) |
| C7 | Fully client-side browser compiler | Scope phase 3 only when requested. Phases 1 and 2 delivered a hybrid service plus browser WASM execution; they did not compile the compiler to WASM. | [Browser playground](../archive/browser-playground.md) |
| C8 | Playground service rewritten from Node to x2c | The original plan promised a handler rewrite after HTTP shipped. HTTP has shipped, but `etc/playground/server.mjs` still owns the service. Reassess this separate example before selecting implementation; preserve its endpoint and container limits. | [Browser playground](../archive/browser-playground.md#service) |

The networking plan's former Notes architecture has no pending implementation.
The [Notes rewrite](../archive/notes-rewrite.md) superseded it. Compiler
ownership, lifetime proof, and prepared-format research retain their existing
reference owners in the [plan index](../README.md).

## Plan review

This is an ownership record, not a feature design or a new requirement.
Existing binding, ABI, JSON, ownership, and staging contracts remain premises.
No new helper, representation, traversal, validation, diagnostic, or fixture
is proposed. Selecting a candidate requires its stated caller and scope.
