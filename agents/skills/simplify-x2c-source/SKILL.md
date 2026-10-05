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

Remove unnecessary machinery while preserving observable behavior. For a
read-only request, investigate and recommend; for an authorized campaign,
follow the removal through source, callers, tests, docs, and generated files.

## Find a connected opportunity

Read [removal patterns](references/removal-patterns.md), relevant source,
tests, and history. Look for duplicated implementations, derived state,
validators, registries, adapters, or intermediate representations whose work
an existing path already performs. Identify what can disappear, why it is
unnecessary, and the production callers whose behavior must remain.

Optional tools can extend a source-backed investigation:

- `find-redundant-validation` lists validator families, local checks, and
  silent guards with the validation rules of `x2c lint`.
- The structure rules of `x2c lint --all` find related source patterns.
- `x2c lint --all` reports comment cleanup candidates.

The finder skills document their runnable commands. Scores measure detector
signals; choose work by the code and runtime operations that can disappear.

## Establish retained behavior and probe the change

Read callers and relevant public documentation. Trace admissible inputs,
identity, ordering, allocation, cleanup, errors, concurrency, symbols,
generated layout, side effects, and hot-path cost where applicable. Tests
written solely for the machinery being removed do not establish an independent
public requirement.

For AST work, consult
[the Match guide](../../replacing-manual-ast-walks-with-match.md)
and trace forms into existing binding, typing, placement, transformation, and
emission. The optional [source graph commands](../../../commands/graph/README.md)
`flows` and `compare` investigate unclear parsed-source paths; reachability
differences require source review, and missing paths do not establish safety.

Apply PR-2, PR-3, FA-3, FA-5, FA-7, FA-8, FA-9, and MA-2 in
[the standard](../../x2c-code-standard.md). Prototype the connected
change and run focused translation, generated-C, compilation, or runtime
checks that distinguish it. Keep only adapters with necessary behavior;
recreating old distinctions through modes and callbacks may defeat the goal.

Apply PR-4 and PR-10 in the standard to validation and compatibility.

## Complete and verify the removal

Follow the same cause through private APIs, state, helpers, diagnostics,
fixtures, documentation, generated projections, initialization, and cleanup.
Keep tests of valid behavior and deliberate public failures. Refresh affected
artifacts through repository targets after verifying source behavior.

Review and fix the completed authored diff, including the strongest remaining
opportunity for deletion or reuse. Inspect every generated change and follow
root validation and delivery instructions on the final tree.

Report the machinery removed, behavior preserved, and focused evidence. If no
substantial connected removal was supported, report that result plainly.
