> Status: active
> Readable match-declaration lowering works in the isolated worktree. The
> constructor is being simplified and measured against literal AST construction.

# Ordinary quotation construction and adoption

Keep `_match_declare` entirely in source quotations. Its callers keep supplied
binding identities, types and finished children. Anonymous quotation values are
supplied at construction; retained projection work does not mean missing args.

Construct canonical syntax and splices immediately when their existing insertion
forms are available. Keep ordinary placement for free names, private identities,
source anchors, frozen fragments, effects and projections requiring it. Preserve
code-versus-data behavior, diagnostics, evaluation order and public runtime ABI.
Do not add a quotation-to-AST conversion API or another semantic implementation.

## Implementation

1. Simplify the completed quotation envelope to a tag consed onto its AST. Use
   the shared literal builder so fully constant quotations fold to cached Lists.
   Keep the established placement and emitter owners for consuming the carrier.
2. Remove redundant construction work: append with an empty tail, repeated
   insertion dispatch on complete expressions, unnecessary generated branches
   where static input types already establish the case. Review the remaining
   fallback representation against the known projection counterexamples.
3. Measure constant quotes and supplied declarations against equivalent literal
   ASTs. Separate payload construction, necessary carrier cost and projection
   overhead. Measure the readable helper too; do not compare only to the slow
   old quotation-plus-rebuild path. Fix avoidable measured costs before adoption.
4. Retain the readable match helper and remove representation selectors from
   adoption sites. Update focused fixtures and the book for the final internal
   representation and behavior. Add only focused lasting coverage that protects
   actual identity, stage, source or evaluation-order behavior.
5. Review the authored and generated diff; run focused regressions, converged
   self-host validation and the existing publication validation command for local
   adoption. Preserve the original no-publish instruction; no remote publication
   or recurring checks are authorized by this plan.

## Plan review

Existing producers establish canonical List syntax and the caller's finished
children. Existing placement owns binding, hygiene, staging, origins and effects;
existing emission trusts finished placed syntax. No consumer gains a new origin
validator or readiness walker. The work reuses typed insertion, splice and
literal-cache owners and shared declaration normalization. The completed carrier
is necessary to preserve the existing code/data distinction, but should cost one
cell over its payload. Existing projection failures retain their owning paths.
No dedicated diagnostic or recurring validation process is added. Source review
must keep the readable caller as the acceptance criterion throughout.
