# Language features as loosely coupled components

> Status: active
> Branch `gwf/language-components` from `origin/dev` 7e946b86. This plan
> restates the design agreed on 2026-10-07 and directs the salvage of
> reusable work from the exploratory branch `gwf/hooks-spike`, which stays
> unmerged as a reference. `dev` and `main` are untouched until Gary says
> otherwise. Salvage progress is in the log at the end.

## Goal

The compiler kernel keeps the core language machinery. Every other
language feature is a loosely coupled component: one single-purpose file,
written against one thin API, wired into the compiler by a registration
that says "when you meet this construct, call this, and use its result."
A user can write a component in the same form and include it; a shipped
component is the same idea compiled into the compiler. Everyone uses the
same thin API, so the compiler cannot become monolithic again.

## Kernel

1. Lexer and C parser.
2. Binder: scopes, names, identifier resolution.
3. Typing: the conversion engine and member resolution.
4. Control flow and cleanup: `defer`, `try`, `catch`, `finally`, regions,
   transfers, label ancestry, and volatile preservation.
5. Macro and meta substrate: expansion, hygiene, quotations, meta
   execution.
6. Unit assembly: imports, interfaces, pending-code destinations, emission.
7. Hook dispatch.

`try`/`catch`/`finally` stay in the kernel on this branch, as on `dev`.
Whether they later become a component is Gary's open decision; nothing in
this plan depends on it.

## Component contract

- **One file per feature.** A built-in component is `src/component-NAME.x`
  and holds the feature's whole algorithm. A user component is an included
  `.x` file holding its macros, meta functions, and registrations.
- **Registration.** One declaration form, `hook POINT KIND TARGET;`
  (spelling settled in salvage step S2), stored and exported like `keyword`
  aliases, so a nonstatic registration reaches includers and a `static`
  one stays file-local. A built-in component's registration is one `hook`
  line in `etc/builtin-macros.x`, the compiler's built-in include, plus one
  row naming its function in `builtin_targets`. These two lines are the
  only places a built-in component touches outside its own file.
- **Dispatch points.** Each point calls the registered handlers for a kind
  in registration order; a handler declines by returning its input
  unchanged. Points in this plan:
  - `node`: a bound, typed node of a listed kind, during the transform.
  - `claim`: a block declaration whose initializer is a `claim` of the
    registered tag, during binding.
  - `member`: a member-resolution miss on a known receiver type.
  A point or kind outside the listed sets is a registration error.
- **Thin API only.** A component uses the calls in lib/meta.x,
  lib/meta-patterns.x, quotations, and the effects below. Anything else it
  needs becomes a new API entry or stays in the kernel.
- **Ordering rule for generated code.** Code literals are contributed
  before lowering; lowered forms after it.
- **Proof for every move.** Generated C for src, lib, packages, and
  examples stays byte-identical, and the change reports kernel lines
  removed against component lines added.

## Salvage from `gwf/hooks-spike`

Each item is ported into the structure above, not cherry-picked. Spike
commits are cited for reference.

| Step | Item | Spike source |
| --- | --- | --- |
| S1 | Effects as x2c calls: `x2c_code`, `x2c_fresh_name`, `x2c_effect_name`, `x2c_effect_support`, `x2c_effect_initialize` | e548e06a |
| S1 | Node diagnostics with a category: `x2c_diagnostic_fail_at(node, category, message, notes)` | e548e06a, d45c110b |
| S1 | Typing queries from project meta code through a nested request | eb89dcf6 |
| S1 | Region interface in the cleanup walk, with the `try` lowering kept in the kernel on it and `defer`'s landing lowered in the kernel | 4a0b198e (without its move into builtins.x) |
| S2 | The single hook mechanism with the `node`, `claim`, and `member` points, replacing the spike's five separate mechanisms | 87354c57, 441eaece, 1f7618fe |
| S2 | Built-in registration fixes: keys survive the cached reinstall; built-in targets name compiled-in functions; the typed-hook flag is set on both install paths | 441eaece, 9cae0fa1 |
| S2 | Fact registration and lookup: `x2c_fact_record`, `x2c_fact_lookup`, `x2c_member_resolve` | 1f7618fe |
| S2 | `$auto` as `src/component-auto.x` on the `claim` point; the `managed-init` node and its five special cases deleted | 441eaece |
| S2 | `delegate` as `src/component-delegate.x` on the `member` point; the kernel delegate search deleted | 1f7618fe |
| S3 | Pattern values and the shared static-pattern lowering: `x2c_pattern_value`, `x2c_pattern_steps`, `x2c_pattern_nest`, with a fixture client | 2e1bde62, c1ba2997, df25119f |

### Not carried over

- The `try` component and the catch selector built inside it.
- The parse-phase hooks (`hook switch $m;`, `hook function $m;`) and the
  spike's separate `claim:`, `cleanup:`, and `fallback:` mechanisms.
- Components placed in `src/builtins.x`.
- `Compiler.convert_at` (kernel-internal; Gary's open decision).
- The user-space prototypes in plans/hooks-spike/; they stay on the spike
  branch as references.

## Feature extraction order (for the next agent)

After salvage, move one feature per change into its own component file,
in this order: printf Var formats, collection literals, `raise`,
destructuring, string interpolation, runtime static locals, `foreach`,
`with`, `class` defaults, `match` (on the shared patterns), lambda
lowering, protocols with their adapters. Each move follows the contract
and its proof. Classification and touch points per feature are in
`plans/hooks-spike/feature-modules.md` on the spike branch.

## Validation

- Per salvage step: `make build`, focused fixtures for the step, and
  byte-identical generated C for src and lib (a two-round local bootstrap
  refresh, then `make stage-diff-0`).
- Before handoff: `make verify`, `make doc-check`, converged bootstrap,
  generated docs refreshed, clean tree, branch pushed.

## Plan review

The kernel list and component contract restate the agreement Gary
confirmed. Each salvage item is general API or a completed extraction;
nothing in the salvage moves a kernel feature. Built-in registration
touches two lines outside the component file, stated above. No new
validator or recurring gate is added.

## Log

- 2026-10-08: plan written on `gwf/language-components` from 7e946b86.
