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

- Typing queries from project meta code (gap found in wave 1).

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

## Log

- 2026-10-07: merged `origin/dev` `7e946b86`; migrated spike files to
  prefix splices (`@fn(...)`); spike tests pass; pushed `15e561fb`.
- 2026-10-07: wave 1 integrated (W1-A typed hook, W1-B effects API);
  bootstrap and docs refreshed; typed switch ported to the effects API.
