---
name: review-x2c-repo
description: >-
  Survey the repository or one named area of it for latent defects,
  inconsistencies, drift, and things that should be removed, then report what
  reproduces. Use for a post-merge integration review, a
  whole-repository sanity check, or a focused maintenance pass over tests,
  benchmarks, documentation, or examples. Do not use to carry out a broad
  deletion campaign; use simplify-x2c-source.
---

# Review the x2c repository

Inspect the requested scope and report reproduced defects or drift. Reviews
are read-only unless the user also authorizes fixes or a tracked catalog.

## Establish scope and baseline

Use the named subsystem, comparison range, or topic. Without a narrower scope,
cover compiler, runtime, build and tooling, tests, packages and examples,
documentation and site, and release readiness. Recent changes guide discovery
but do not replace the requested coverage.

Inspect current `HEAD` and relevant existing validation evidence. Use focused
non-mutating checks as needed; publication gates are not review baselines.
For broad work, delegate independent read-only discovery, then reproduce its
claims yourself. Name anything left unexamined.

## Inspect and reproduce

Trace concrete questions through current source, consumers, tests, examples,
and the book. Compare related implementations where an unexplained difference
could affect behavior. Reproduce each finding at current `HEAD` before
recommending work, and rank it by the observed consequence. Distinguish
refuted claims and unresolved questions from findings.

Use root design and validation rules and the relevant
[philosophy](../../x2c-philosophy.md). Recommend validation only when the
existing behavior violates a deliberate public rule, accepts wrong output,
corrupts state, or crosses an unsafe native boundary. Canonical AST Lists from
compile-time Lisp are accepted by structure, as documented under
[Macro-visible syntax](../../../docs/src/reference/language.md); their origin
is not a defect.

For parser, macro, Lisp, Match, transform, generator, or emitter work, consult
[the Match guide](../../replacing-manual-ast-walks-with-match.md). Trace
canonical forms into their ordinary semantic operations. The optional
[source graph commands](../../../tools/x2c-graph/README.md) `flows` and
`compare` expose parsed-source paths worth inspecting; shared paths do not
establish semantic equivalence, and missing paths do not establish safety.

## Report or repair as requested

For review-only work, report findings, consequences, recommended repairs, and
actual coverage without modifying tracked files. A requested durable catalog
follows [plans/README.md](../../../plans/README.md) and records open findings
with reproductions, refuted claims with reasons, and areas verified clean.

For authorized fixes, use `fix-x2c-bug` where diagnosis is needed and complete
unambiguous mechanical corrections within the request. Raise unresolved
consequential design choices or compatibility changes beyond authorization.
Describe connected removal opportunities for `simplify-x2c-source` rather than
turning a review into an unrequested deletion campaign.

The review is complete when its requested scope has been examined and its
findings verified. Report remaining gaps plainly; a green check alone does
not establish repository health.
