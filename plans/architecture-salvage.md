# Salvage from the declined compiler redesign

> Status: active - 2026-09-15. Gary declined the from-scratch compiler
> redesign on 2026-09-14; no plan was written for it. Three pieces of it
> survive as incremental work, delivered as separate PRs in this order.
> Interface files, the fourth piece, already shipped as
> `plans/archive/unit-interfaces.md`.

## 1. One file initialization mechanism

A file-static initializer passes through three unrelated layers today:

- `src/cache.x` strips the initializer, records the assignment, and
  synthesizes one helper function per definition
  (`_rewrite_file_scope_statics`, `_queue_static_initializers`).
- `src/generate.x` orders the call into one of four phases (protocol, early,
  middle, late) behind `_init_guard_`, the `_file_init_` constructor, and the
  init prelude placement.
- `src/emit.x` lifts the assignment into a generated C macro pair
  (`_initializer_macro`) so a native macro argument expands once.

Both defects fixed in b4debf9 lived at those seams: the initializer call was
emitted outside the `#if` that enclosed its definition, and the queue was
keyed by binding, so only the last branch of a conditional group kept its
initializer. Neither is visible in any single file.

The result to reach is one ordered list of initialization statements with one
emission path, and each entry carrying the conditional directives that
enclose it. What must survive:

- Cache-slot ordering. An initializer that depends on the String or List
  canonicalizer runs after it; `Compiler.setup_cache_init` owns that today.
- The dependency walk between file statics, including the cycle diagnostic.
- The `__builtin_choose_expr` conversion selection, which is why the macro
  pair exists at all. Moving it is not part of this change.

Validation: `conditional-private-split` and the existing initializer fixtures,
`make verify-fixtures`, and the self-translation comparison. Emission changes,
so publication takes two gate rounds.

## 2. Cleanup lowering out of `src/emit.x`

`emit.x` carries a cleanup stack, cleanup labels, break/continue barriers, a
cleanup path, and volatile preservation. That is semantic lowering performed
during text emission, where match templates do not apply and `--dump` shows
nothing. Expanding `defer`, `$auto`, and `finally` into an ordinary transform
pass would make the result inspectable as AST and shrink the least readable
part of the back end.

This is a project, not a cleanup. Defer ordering and the `volatile`
interaction are subtle; a `$let` inside `try` needed an emission fix on
2026-09-15. Scope it on its own evidence before starting.

## 3. Collection reuses the real parse configuration

`src/collect.x` builds a shadow `Compiler` and hand-copies state into it
(`_parse_segment`). The scripting work had to propagate `script`, `shebang`,
and `script_main` by hand, and binding ids still collide between collection
and the full parse. The repair is contained: collection configures itself
from the same request the full parse uses, rather than copying fields.

The general "parse separated from bind" idea from the redesign is not part of
this; only the duplication it reacted to.

## Declined, with reasons

- A struct IR after binding. The cons AST with match templates is the
  compiler's main asset, and the IR's payoff was peak memory, which nothing
  is short of.
- Ordered lowering passes replacing the fixed point. The fixed point costs
  about 0.1 s per unit and buys composability; a pass list moves ordering
  constraints somewhere nobody can verify.

## Plan review

The work deletes machinery rather than adding it: item 1 removes two of three
initialization layers, item 3 removes a hand-copied shadow configuration.
Item 2 moves existing behavior into the transform stage that already owns
lowering. No new validator, diagnostic, or artifact is proposed. Each item
ends by reviewing its authored diff before publication validation.
