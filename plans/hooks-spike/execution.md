# Thin API spike: execution

> Status: active
> Private branch `gwf/hooks-spike`, pushed to origin. Gary authorized
> orchestrated implementation on this branch on 2026-10-07; `dev` and `main`
> are untouched until he says otherwise. Scope is `thin-api.md`, in its
> ranked order, each entry proven by a client named in `feature-modules.md`.

## Rules

- Follow root `AGENTS.md`: idiomatic x2c, no hand-edited bootstrap, delete
  what an entry replaces, focused checks per task, and review the authored
  diff before each pushed checkpoint.
- Every new entry is used by a real client in the same wave.
- Measure what an entry costs when unused and what its client costs per use.
- Stop and report when blocked; no side quests.

## Wave 1: typed node hook, effects, diagnostics

- **W1-A typed node hook.** Registration for a node kind at the transform
  phase; the hook may decline; a changed result is re-dispatched.
- **W1-B effects as x2c calls.** Fresh names, unit support, file
  initialization, and diagnostics at a node, as `lib/meta.x` calls over
  code-value carrier effects.
- **Proof.** String switch as one typed-phase component: one meta layer,
  label diagnostics, C-string subjects, null matching `case ""`. Compare its
  cost per use with the built-in prototype.

## Later waves (ranked by `thin-api.md`)

- Patterns to `if` tests, with `catch` selection and `match` arms as clients.
- Fact registration at collection, with `delegate` as the first client.
- Declaration-position hook, with `$auto` as the client (deletes
  `managed-init`).
- Conversion at a position.
- Cleanup participation, with `try`/`finally`.
- Reader-prefix hook, with quotations.

## Wave 1 result

- Typed node hook: `hook <switch> f;` registers meta function `f`; it may
  decline by returning the node; a changed result is bound and re-stepped.
  Unused: no measurable cost (src/generate.x 5,741.4 M before and after).
  A declined node costs about 1.2 M instructions.
- Effects API in lib/meta.x: `x2c_code`, `x2c_fresh_name`,
  `x2c_effect_name`, `x2c_effect_support`, `x2c_effect_initialize`,
  `x2c_diagnostic_fail_at`. Code without effects pays nothing measurable.
- Proof: `typed-switch.x` is one typed-phase component with a fresh name,
  C-string subjects, null matching `case ""`, and a label diagnostic at the
  label. Per use: 17.04 M instructions, against 7.76 M hand-written and
  6.55 M for the built-in prototype.
- New gap: project meta code cannot run typing queries (`x2c_type_resolve`
  and siblings fail in the helper), so a user-include component cannot ask
  whether a typedef reaches String.
- Bootstrap refreshed on the branch; 26 focused fixtures pass.

## Wave 2

- W2-A: project meta code asks typing queries through a nested request on
  the reply pipe, answered by the compiler at the call site (about 0.17 M
  instructions and 30 us per query). The typed switch now declines a named
  subject that does not reach a C string.
- W2-B stopped before editing: deleting `managed-init` through a general
  declaration hook would change seven fixture diagnostics (all categories,
  five positions) and tax every declaration with a meta call. Decision: add
  a category argument to the diagnostic API; replace `managed-init` with a
  generic claimed-initializer node whose tag selects a registered
  declaration hook, so only claiming declarations call it and unconsumed
  claims report at today's positions; let built-in components register
  hooks that survive reinstall and name compiled-in functions.
- W2-B result: `managed-init` and its special cases are gone. `$auto`
  produces `(claim auto MESSAGE VALUE)`; a 30-line component in
  src/builtins.x, registered by `hook <auto> builtin_auto_declaration;` in
  etc/builtin-macros.x, lowers it through the thin API. Generated C and all
  `managed-init-*` diagnostics are byte-identical. Kernel: 104 added, 114
  removed. `$auto` per use: 17.13 M before, 17.32 M after; unused hooks cost
  nothing measurable.

## Wave 3

- W3-A: `match-component.x` lowers a `match` whose arms are all static
  patterns to nested `if` tests inside `switch (0) { default: ... }`, with no
  Match runtime call; every other `match` is declined with byte-identical C.
  Semantics match the book on its test and on all 11 match fixture programs
  with output. Translation per use: built-in 12.38 M, component 52.15 M,
  the component's output written by hand 45.14 M. Runtime: 9 to 11 percent
  faster than the built-in.
- Cost floor found: a typed-phase component pays to bind and type the code
  it returns, so it cannot translate cheaper than the same code written by
  hand. The built-in emitter writes its tests as C text and avoids this.
  The carrier already has a `lowered` stage; an API entry that returns
  lowered code would remove the rebinding where a component can produce
  lowered forms.
- Defect found in the built-in `match` (not caused by the spike): a `defer`
  in an arm that reads an arm binder fails in C with an undeclared
  identifier.

## Log

- 2026-10-07: merged `origin/dev` `7e946b86`; migrated spike files to
  prefix splices (`@fn(...)`); spike tests pass; pushed `15e561fb`.
- 2026-10-07: wave 1 integrated (W1-A typed hook, W1-B effects API);
  bootstrap and docs refreshed; typed switch ported to the effects API.
- 2026-10-07: W2-A integrated; bootstrap and docs refreshed.
- 2026-10-07: W2-B integrated (claims, declaration hook, category argument).
- 2026-10-07: W3-A integrated (match component, pattern values); bootstrap refreshed.
