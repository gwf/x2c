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

- `find-redundant-validation --frameworks` groups validator families; ordinary
  mode finds local checks, and `--producer-consumers` traces repeated guards.
- `tools/audit-source-bloat.py` finds related source patterns.
- `find-comment-slop` identifies comment cleanup opportunities.

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
emission. Use `x2c-graph flows` or `x2c-graph compare` to investigate unclear
parsed-source paths; reachability differences require source review.

Prefer deletion, direct use of existing code, then one shared operation.
Compile-time generation helps when it replaces real implementations sharing
storage, ownership, failure, and lifetime behavior. Prototype the connected
change and run focused translation, generated-C, compilation, or runtime
checks that distinguish it. Keep only adapters with necessary behavior;
recreating old distinctions through modes and callbacks may defeat the goal.

Apply root validation rules: a more specific error alone does not justify
keeping a validator. Ask before changing public behavior, API, ABI, or caller
obligations beyond the request.

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
