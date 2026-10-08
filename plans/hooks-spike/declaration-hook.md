# Claims and the declaration hook

> Status: reference
> Wave 2 entry W2-B of `execution.md`, on private branch
> `w2b-declaration-hook` from `gwf/hooks-spike` `eaee0a7e`, 2026-10-07.
> The proof is `$auto` (`etc/builtin-macros.x`, `src/builtins.x`); the
> user-level probe is `claim-noted.x` with `claim-noted-test.x`.

## Spelling

```x2c
macro Expression $auto(Expr $value) =>
  $(list 'expr nil
    (list 'claim 'auto
      "managed initializer requires a complete block-local initializer"
      $value));

hook <auto> builtin_auto_declaration;
```

A claim, `(claim TAG MESSAGE VALUE)`, replaces the `managed-init` node. A
`hook <TAG> f;` whose TAG is not a typed node kind (`typed_hook_kinds`)
registers `f` as the declaration hook of claim TAG. The tokenizer already
reads `<TAG>` after `hook`, so no new syntax was needed. The message travels
in the claim rather than in the registration, so an unconsumed claim is
reported without a lookup, even when no hook is visible.

## Semantics

- A claim has the type of its value (`Resolve._claim`).
- Binding, not transformation: after a block declaration binds
  (`_declaration_item` and constructed `_bind_declaration`), each
  declarator whose complete initializer is a claim, through `expr` shells
  and parentheses, goes to the hook of its tag. The hook receives that
  declarator alone, `(declare BASE (bindings (op = BIND VALUE)))`, and
  returns it to decline or returns block items, which bind in place. The
  kernel splits the declaration as before: ordinary declarators before a
  hooked one end their own declaration.
- Binding is the phase because the replacement must exist before region
  analysis and `defer` lowering read the block, which is where today's
  lowering ran; the generated C stays identical.
- A claim no hook takes reaches transformation and reports its MESSAGE as a
  `parse:` error at the enclosing statement, which is today's position.
- Declarations without a claim pay the existing structural check only; no
  meta call is made.

## Built-in hooks

- `_record_alias` stores the key `parse_keyword_definition` returns, so
  `hook` keys (`hook:switch`, `hook:<switch>`, `claim:<auto>`) survive the
  cached reinstall of built-in sources.
- In built-in source, a hook names its target by spelling; the name
  resolves through the session's built-in targets (`builtin_targets`).

## Node diagnostics take a category

`x2c_diagnostic_fail_at(node, category, message, notes)`; the helper sends
`(at NODE CATEGORY)`. `$auto` reports `<parse>` and `<protocol>` through it,
so all seven `managed-init-*` diagnostics are byte-identical. The signature
change needed a two-round local bootstrap refresh: the seed rejects a
`lib/meta.x` prototype that does not match its own compiled target.

## Result

- Generated C: after the refresh, `bootstrap/`, stage 0, and stage 1 are
  identical; against `eaee0a7e`, only the C of edited modules changed, so
  every `$auto` in `src/` and `lib/` emits the same C.
- Lines (`git diff --numstat`): the claim and hook change adds 134 and
  removes 115. Kernel files (`parse.x`, `macros.x`, `expressions.x`,
  `transform.x`, `statements.x`) add 104 and remove 114; the component
  (`builtins.x`, `builtin-macros.x`) adds 30 and removes 1. The category
  argument adds 31 and removes 21.
- A user claim works through the project meta helper (`claim-noted.x`).

## Measurements

Stage-0 compilers built from their own converged bootstraps, `eaee0a7e`
(before) and this branch (after), in copies at equal path lengths;
`bench/measure.sh`, one warm-up, minimum of five.

| Translation | Before | After |
| --- | ---: | ---: |
| `src/generate.x`, 9 `$auto` uses | 5,749.8 M | 5,744.2 M to 5,755.2 M (two runs) |
| `src/parse.x`, its own copy (source differs) | 8,461.3 M | 8,399.0 M |

Per function, slope from N=50 to N=400 (`bench/gen-auto.py`):

| Form | Before | After |
| --- | ---: | ---: |
| `Array items = $auto([x, i]);` | 17.13 M | 17.32 M |
| The same with a hand-written `defer` | 15.69 M | 15.69 M |

`$auto` costs 0.19 M instructions more per use: one in-process meta call
and the rebinding of the declarator. A unit without claims is unchanged
(the hand-written units measure about 10 M lower after, at both sizes).

## Limits

- Any `hook <TAG>` that is not a node kind is a claim hook, so a misspelled
  typed node kind registers an unused claim hook instead of an error.
- The hook's declaration rebinds: its bound declarator binds again in
  place, as quotation holes do for the typed node hook.
- The constructible form changed from `(managed-init EXPR)` to
  `(expr () (claim auto MESSAGE EXPR))`; the language reference says so.
