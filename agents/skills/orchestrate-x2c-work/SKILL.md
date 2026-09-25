---
name: orchestrate-x2c-work
description: >-
  Run several independent x2c changes in parallel with subagent workers in
  isolated worktrees, then integrate them yourself in batches with one gate
  run per batch. Use when a session has two or more separable changes, a
  campaign with independent deliverables, or contention on dev from other
  sessions. Do not use for a single change; use the matching task skill.
---

# Orchestrate and integrate x2c work

The orchestrator splits the work, runs workers in parallel, and is the only
integrator. Workers build and check their own change; only integration merges
`dev`, runs the gate, and pushes. One gate run then covers several changes,
and the session stops churning on `dev`.

## Split the work

List the changes and the files each one touches. Changes that share files, or
where one needs another's result, go in order; everything else runs at once.
A change that adds a native target or compiler capability is its own step:
see [Capabilities](#capabilities).

If another session works on `dev`, agree on file boundaries with it before
editing shared files, and tell it when a shared file is clear again.

## Brief each worker

Launch each worker with worktree isolation. Tell it to:

- run `git fetch origin` and `git checkout -b <branch> origin/dev` first, and
  to report at once if a git command is refused;
- run `mkdir -p debug && make build-safe` before building;
- make only its change and run `make build`, the fixtures and unit tests it
  affects, and `git diff --check`;
- not merge `dev`, commit, push, or run `tools/gate-state.py` or
  `tools/land-dev`, which refuse to run in `agent-*` worktrees;
- save its patch against its branch point, never against the current
  `origin/dev`, and only for files it authored:
  `git diff --binary $(git merge-base HEAD origin/dev) -- src lib etc unittest docs/src/guide docs/src/reference plans`;
- save the patch in the session scratchpad. The gate deletes
  `unittest/build/`.

A diff against the moving `origin/dev` includes the reverse of commits that
landed after the worker branched and silently undoes other sessions' work.
Generated docs, `site/`, and `bootstrap/` are regenerated at integration.

## Integrate a batch

A batch is every patch finished since the last landing. While other workers
are still running, hold finished patches rather than landing each one; land
early only for a capability step or a patch another worker needs. Tell each
worker the gate runs once, at integration, so its own checks stay small.

1. Create a branch from current `origin/dev` and apply each patch with
   `git apply --index -3`, one commit per change. Resolve conflicts by
   keeping both sides' intent; generated files are regenerated, not merged.
2. Run `make build` right away. A patch from an older base can call code
   another change deleted; a three-way apply does not catch that.
3. Review the combined authored diff for overlap, repeated checks, and
   leftover machinery.
4. Run `tools/land-dev "<bootstrap refresh message>"`. It merges `dev`,
   regenerates docs, runs the gate with one retry for a two-round refresh,
   commits the refresh, and pushes only when the gate passes and the tree is
   clean. A rejected push retries from the merge.
5. After a failed gate, read `debug/gate.log`, fix the cause in the batch,
   and run `tools/land-dev` again. Never rerun an unchanged gate in a loop;
   `tools/land-dev` already retries once for a two-round refresh. Clear the
   worktree before switching branches.

## Capabilities

A change that adds a native target, a `meta` prototype the bootstrap lacks,
or any compiler behavior that current source depends on goes on its own
branch. Refresh the bootstrap there and prove it with a stage-two build
(`tools/land-dev` does both) before it reaches `dev`. Callers follow in a
later batch. Each step then stays one revert away from a compiler that builds
the current source.

## Limits

Workers cannot write to worktrees the orchestrator creates; each needs its own
isolated worktree. A worker can branch from a local integration branch, because
worktrees share one repository. When the permission check refuses a worker's
git commands, restart it or do that change in the orchestrator's worktree.
