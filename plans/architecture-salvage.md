# Salvage from the declined compiler redesign

> Status: active - 2026-09-15. Gary declined the from-scratch compiler
> redesign on 2026-09-14; no plan was written for it. Three pieces of it
> survive as incremental work, delivered as separate PRs in this order.
> Interface files, the fourth piece, already shipped as
> `plans/archive/unit-interfaces.md`. Item 1 landed as PR #57 and item 3 as
> PR #58; item 2 remains, and needs scoping on its own evidence first.

## 1. One file initialization mechanism (queue done, PR #57)

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

Delivered so far: the four phase queues and their four `Compiler` methods
became one queue with `Compiler.add_init(phase, stmt)` and
`Compiler.init_statements(phase)`. Generated C is byte-identical for every
unit that did not change.

Measured and rejected during that work: inlining each initializer statement
into the file initializer, deleting the per-initializer helper function and
its macro pair. The helper's position at the declaration site is load-bearing
for the host preprocessor. `unittest/compiler-fixtures/static-native-source.x`
initializes a static from `(int)__COUNTER__`; running the assignment from the
initializer body instead expands the macro at a different point in the file,
and the program printed `2 41 1 1 1` against the expected `0 41 2 1 2`.
`__LINE__` and `__FILE__` carry the same exposure. Any future attempt has to
keep the initializer's text where the author wrote it.

Still open under this item, both emit-side and better taken with item 2:

- Skipping the `_x2c_initializer_choice` macro pair when the captured body
  uses each operand once, which is the common case. It costs six lines of
  generated C per initializer today and lifts nothing.
- The lazy entry guards `_patch_func_with_init` installs, kept as the
  portable fallback to `__attribute__((constructor))`, and the
  `_cache_reachable_function_ids` analysis that decides where they go.

What must survive:

- Cache-slot ordering. An initializer that depends on the String or List
  canonicalizer runs after it; `Compiler.setup_cache_init` owns that today.
- The dependency walk between file statics, including the cycle diagnostic.
- The `__builtin_choose_expr` conversion selection, which is why the macro
  pair exists at all. Moving it is not part of this change.

Validation: `conditional-private-split` and the existing initializer fixtures,
`make verify-fixtures`, and the self-translation comparison. Emission changes,
so publication takes two gate rounds.

## 2. Cleanup lowering out of `src/emit.x` (remaining)

`emit.x` carries a cleanup stack, cleanup labels, break/continue barriers, a
cleanup path, and volatile preservation. That is semantic lowering performed
during text emission, where match templates do not apply and `--dump` shows
nothing. Expanding `defer`, `$auto`, and `finally` into an ordinary transform
pass would make the result inspectable as AST and shrink the least readable
part of the back end.

This is a project, not a cleanup. Defer ordering and the `volatile`
interaction are subtle; a `$let` inside `try` needed an emission fix on
2026-09-15. Scope it on its own evidence before starting.

## 3. Collection reuses the real parse configuration (done, PR #58)

`src/collect.x` built a shadow `Compiler` and hand-copied state into it. The
three script fields became one `ScriptUnit` record that every compiler of the
unit inherits, with `Compiler.tokenize` activating it on the file that
carries the shebang; `include_dirs` inherits the same way; and the borrowed
segment state became `Compiler.take_unit_state` and
`Compiler.return_unit_state`. `_parse_segment` lost 22 lines and generated C
did not change.

Still open in the same area: binding numbers collide between collection and
the full parse, so a graph keyed by number alone mixes the two passes. The
general "parse separated from bind" idea from the redesign is not part of
this.

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
