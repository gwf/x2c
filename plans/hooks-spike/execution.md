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

## Log

- 2026-10-07: merged `origin/dev` `7e946b86`; migrated spike files to
  prefix splices (`@fn(...)`); spike tests pass; pushed `15e561fb`.
