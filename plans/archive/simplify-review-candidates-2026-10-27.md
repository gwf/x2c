# Simplify the duplicate owners the 2026-10-27 review listed

> Status: done
> Published to `dev` on 2026-10-27 in `76cca9ad2` with its bootstrap
> refresh. Candidates 3, 4, and 6 landed; candidate 1 kept its walkers and
> merged the `available` and `seen` maps; candidates 2 and 5 were rejected
> for the reasons recorded below. `agent-pr-check` passed on the integrated
> tree, and 1307 compiler fixtures and the split suite passed before it.

## Context

The review of `origin/dev` (`0397c7277`) found no defects but listed
duplicate owners and manual AST walks that PR-2, PR-3, and PR-4 in
[the standard](../../agents/x2c-code-standard.md) say to consolidate. Gary
asked for one plan rather than several sessions. Each claim below was read
in current source first; a claim that does not survive reading is rejected
and recorded so the next review does not raise it again.

## Candidates

### 1. Two declaration walkers in `src/generate/dependencies.x`

Claim: `_collect_declared` and `_source_declarations` are parallel
recursive walkers over the same shapes.

Reading: both match `function`, `declare`, and `typedef` nodes and recurse
through every other child. They record different facts at different
times. `_source_declarations` runs once over the whole unit and stores each
static declaration by key. `_collect_declared` runs per emitted node and
per forwarded declaration, recording what a reader at that position can
already see. The arm policies also differ: the first keeps static objects
only, the second keeps every declarator and classifies single-declarator
`declare` forms by function type. Routing both through one walker would
need a mode per arm, which the removal patterns reject.

Decision: keep the walkers. The connected duplicate is the bookkeeping
around them: `Forward.available` (declared before this point) and
`Forward.seen` (already forwarded) answer the same question, and every
consumer tests both. They merge into one `declared` map. The
`declared[key] = 1` write in `_declaration` is redundant with the
`_collect_declared` call that follows it on the same declaration and goes.

### 2. `_source_type_definition` in `src/emit/initialization.x`

Claim: it hand-copies the `$ast.walk` worklist from `src/ast-rewrite.x`.

Reading: it does, with one difference. Its `expr` arm visits only the
content child and skips the type slot, because an expression whose type is
an anonymous aggregate carries a `(fields ...)` body in that slot without
being a source definition. `$ast.walk` can skip all of a node's children
with `continue`, but not one of them. Writing the skip through the macro
would depend on reassigning the walk variable mid-body, which the macro
does not document.

Decision: rejected. A comment at the function records why the hand walk
stays.

### 3. The lone `seq` unwrap

Claim: `(seq ?only)` single-item unwrap is spelled at eight sites.

Reading: six sites unwrap a one-item `seq` and otherwise keep the node:
`src/parse/binding.x` (two), `src/parse/functions.x`,
`src/macros/invocations/targets.x`, `src/macros/rewrites.x`, and
`src/macros/templates.x`. Two use the match differently and stay:
`src/meta-sdk/rewrites.x` asks whether the template is exactly a one-item
`seq`, and `src/compiler/declarations/production.x` recurses through nested
`seq` wrappers as one arm of a larger match.

Decision: `Ast.lone_item` in `src/ast.x` owns the unwrap; the six sites
call it.

### 4. The optional-reference head test

Claim: `type.car() == <opt-ref>` appears at eleven sites while `lib/type.x`
owns only `is_reference`.

Reading: ten occurrences at nine sites in `src/expressions/calls.x`,
`access.x` (two), `conversions.x` (two), `operators.x` (four), and
`src/parse/declarators.x`. `Type.is_reference` already spells the same test
as half of its definition.

Decision: `Type.is_optional_reference` joins `Type.is_reference` in
`lib/type.x`, which is defined through it, and the ten occurrences call it.
This adds a runtime operation and changes no existing signature. The
generated library reference is refreshed with `make doc-generate`.

### 5. Numeric text beside `String.try_long` and `String.try_double`

Claim: `lib/json.x`, `lib/datum.x`, `lib/type.x`, and `lib/dispatch.x` each
read numeric text beside the String parsers in `lib/string/number.x`.

Reading: `try_long` and `try_double` parse a whole NUL-terminated String,
accept surrounding whitespace and C radix prefixes, and produce `long` or
`double`. None of the four sites can use that contract.

- `json.x` `_number` reads a prefix of the remaining input after its own
  grammar check, narrows to `int`, and falls back to `unsigned long`.
- `datum.x` `_decode_number` reads `long double`, `unsigned long long`,
  and `long long` by tag.
- `type.x` `numeric_literal_value` reads at the literal's own precision
  (`float`, `double`, `long double`) and the text may carry a suffix.
- `dispatch.x` `_write_float_repr` round-trips `long double` candidates.

Decision: rejected. The widths and prefix parses are the policy; the
parsers would need modes to serve them.

### 6. `strstr` in `lib/string/cursors.x`

Claim: `_end` uses `strstr` beside `_find_bytes` in `lib/string/search.x`.

Reading: confirmed. `String.find` and `String.find_within` search by
length, so a separator after an embedded NUL is found by `find` and missed
by `split`.

Decision: `_end` calls `String.find_within`, the public owner, and the
`strstr` call goes. The naive byte search already serves `find`; `split`
joins it.

## Implementation

One commit per candidate group is unnecessary; the change is small enough
to land as one authored commit plus the artifacts the gate regenerates.

1. `src/generate/dependencies.x`: replace `available` and `seen` with
   `declared`; update the record comment.
2. `src/emit/initialization.x`: comment on the deliberate hand walk.
3. `src/ast.x`: add `Ast.lone_item`; rewrite the six sites.
4. `lib/type.x`: add `Type.is_optional_reference`; rewrite the ten
   occurrences; `make doc-generate`.
5. `lib/string/cursors.x`: `_end` through `find_within`.

## Validation

- `make build-safe`, then `(cd unittest && ./test-all split_suite)` and the
  compiler fixtures the gate runs.
- `tools/gate-state.py ensure agent-pr-check` on the integrated tree,
  which also refreshes `bootstrap/` and compares the self-hosted build.

## Delivery

Direct to `dev`: fetch and integrate `origin/dev`, ensure the gate, push
`HEAD:refs/heads/dev`, then archive this plan with its outcome.
