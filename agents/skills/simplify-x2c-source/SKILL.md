---
name: simplify-x2c-source
description: >-
  Remove over-engineering from hand-authored x2c source by deleting duplicate
  owners, derived state, redundant paths, obsolete internal APIs, defensive
  validation, parallel implementations, and boilerplate that current language
  features can replace. Use for broad simplification campaigns or requests to
  make src/ and lib/ substantially smaller without changing behavior.
---

# Simplify x2c source

Remove concepts and machinery the program no longer needs. A smaller score,
shorter spelling, dead field, or isolated wrapper is not the result. A real
simplification removes a type, path, state, implementation family, duplicate
owner, runtime operation, or reconciliation step while preserving observable
behavior.

For a read-only audit, inspect and report candidates without editing. For an
authorized campaign, follow the connected consequences through source, tests,
documentation, symbols, and generated artifacts.

## Start from history and module shape

Read [`references/removal-patterns.md`](references/removal-patterns.md), then
inspect recent large additions, regressions, and modules that acquired new
validators, registries, caches, policy objects, adapters, or intermediate
representations. Select a connected subsystem whose behavior can be traced
end to end.

Write the strongest plausible deletion hypotheses before changing code. Each
hypothesis must name:

- the complete machinery expected to disappear;
- the current fact or owner that makes it unnecessary; and
- the production consumers whose behavior must remain.

Rank by concepts and runtime work that can be removed, not by scanner
confidence, line count, or ease. Formatting, zeroing changes, unused fields,
and unrelated small wrappers are leftovers, not an architectural campaign.

## Use scanners as evidence, not assignments

The repository keeps three read-only tools because each can expose a real
pattern, but none chooses work:

- `find-redundant-validation --frameworks` groups connected validator
  families; its ordinary mode finds exact impossible checks and weaker local
  candidates without adding their scores together;
- `tools/audit-source-bloat.py` widens an existing source/history hypothesis;
  its score is detector strength, not architectural value; and
- `find-comment-slop` checks comment rules and exact repeated prose. Use it for
  comment cleanup, not as evidence that a source subsystem is over-engineered.

Run a scanner only when its pattern bears on a hypothesis already supported by
source or history. Never choose the first or highest result, and do not run all
three merely to show that an audit was comprehensive.

## Reconstruct the retained behavior

Read the relevant modules, callers, tests, and history completely. Describe
what enters, what leaves, what can fail, and which phase or object establishes
each fact. Trace observable identity, ordering, lifetime, ownership,
diagnostics, symbols, generated layout, concurrency, and hot-path cost.

Inventory the machinery that provides those results: types, fields, caches,
flags, registries, wrappers, adapters, validation, cleanup, generated rows,
tests, and public names. At each step ask whether the information is original,
derived, duplicated, or retained only for a consumer that no longer exists.

For an AST family, read
`agents/replacing-manual-ast-walks-with-match.md`, then trace every producer to
the ordinary semantic operations that bind, type, place, transform, and emit
it. Parser output, macro output, compile-time Lisp, and transformed syntax
should share the canonical AST and those operations. A separate decoder,
validator, repair walk, or semantic constructor is a deletion candidate
unless it owns genuinely different syntax or operational work. Use
`x2c-graph flows` for one returned value and `x2c-graph compare` for two
supplied entries when the source path is not obvious; treat reachability
differences as places to read, not findings.

Tests written solely for machinery under suspicion are evidence about that
machinery, not independent production consumers. An earlier custom diagnostic
for invalid source is required only when public behavior deliberately promises
it or the existing path could accept wrong output, corrupt state, or cross an
unsafe native boundary.

## Design and probe the smaller program

State the intended result directly:

> `<owner>` establishes `<fact>`; `<machinery>` disappears; `<consumers>` use
> `<direct path>`.

Prefer deletion, then direct use of the existing owner, then one ordinary
shared operation. Use compile-time generation only when one definition
replaces multiple real implementations with the same storage, ownership,
failure, publication, and lifetime rules.

Prototype a connected deletion before committing to it. Run the smallest
translation, generated-C inspection, compilation, runtime probe, or focused
test that distinguishes the proposed design. Similar control flow is not
enough: compare admissible inputs, output identity, allocation, cleanup,
threading, errors, side effects, symbols, and layout.

If the probe fails, identify the exact operation or observable difference. Try
the supported direct form before restoring the old layer, and retain only the
adapter or policy that still performs necessary work. Reject a consolidation
that needs modes, callbacks, or wrappers merely to recreate every old
distinction.

Stop and request approval when the smaller design changes public behavior,
public API, ABI, or caller obligations beyond the request.

## Remove the complete slice

Once the owner and retained behavior are proven, delete every consequence:
private APIs, state, helpers, branches, validators, diagnostics, fixtures,
documentation, generated projections, initialization, and cleanup. Search the
whole repository for the same cause rather than stopping at the first site.

Do not replace a redundant validator with an assertion or shorter validator.
Do not preserve a private abstraction merely because deletion crosses files.
Do not restore dead source to satisfy stale symbols, fixtures, or bootstrap
output; refresh derived artifacts through their documented targets after the
source behavior is proven.

## Validate the completed result

Run focused behavior checks before refreshing expectations. Then update only
affected artifacts through repository targets and inspect every generated
diff. Never hand-edit `bootstrap/` or generated `lib/x2c.x`.

Challenge the final design against the original request, complete diff,
relevant history, rejected probes, and the strongest plausible missed
deletion. Reproduce any new concern before changing the tree again. Finish
with the publication command required by the root `AGENTS.md` once, on the
exact final tree.

Report the machinery that disappeared, the behavior that remains, the focused
evidence, total authored and generated changes, and any concrete blocker that
kept a substantial candidate. If no connected machinery disappeared, say the
campaign did not find an architectural simplification; do not present cleanup
leftovers as the result.
