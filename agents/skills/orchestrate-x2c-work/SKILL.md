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
Give each worker its own files. A rename whose callers span several workers'
files is done by the orchestrator at integration.
For local dependencies on a new compiler capability, see
[Capabilities](#capabilities).

If another session works on `dev`, agree on file boundaries with it before
editing shared files, and tell it when a shared file is clear again.

## Brief each worker

Launch each worker with worktree isolation. Tell it to:

- branch from the orchestrator-selected starting revision: current dev for
  independent work, or a local capability commit for dependent work. Record
  that exact revision for the handoff;
- initialize a fresh compiler with `make build-safe` before using `builds/0`,
  then choose focused builds or tests that answer its implementation questions;
- prove its change with the cheapest complete check. For a refactor, move, or
  rename, `make build && make stage-1 && make stage-diff-1` byte equality is
  the proof. Add the suites or fixtures that exercise changed runtime or
  diagnostic behavior, and before/after instruction counts on a hot path. Do
  not run `make verify` or `make commands-check` unless the change touches
  what only they cover; the integration gate runs them once for the batch;
- split a file as a move commit with no edits inside the moved text, then a
  commit that settles crossings, the header, and section order;
- stop and report, with evidence, when the assigned change would break a
  deliberate behavior or contract, rather than forcing it;
- keep scratch files in its own subdirectory of the session scratchpad;
- make only its assigned change. Private checkpoint commits are unrestricted
  under the root local-work policy;
- not merge `dev`, push, or run `tools/gate-state.py` or `tools/land-dev`;
  shared integration and publication belong to the orchestrator;
- hand over its commits or a patch containing all authored committed and
  uncommitted changes against the recorded starting revision. For a patch,
  use `git diff --binary <starting-revision> -- <authored-paths>` and include
  any new untracked authored files;
- save patches in the session scratchpad, outside `unittest/build/`, which
  the gate deletes.

A diff against a moving `origin/dev` can reverse other sessions' changes.
Generated docs and final bootstrap artifacts are regenerated at integration;
local bootstrap refreshes needed for development remain available to workers.

## Integrate a batch

Combine finished work into a coherent batch rather than landing each worker
separately. Several phases of one campaign can share a batch: local commits
need no gate, and each landing costs a full gate run. Dependent workers can
consume local capability commits before any publication. The gate runs on the
completed integrated tree; commit organization is an implementation choice.

1. Integrate current `origin/dev` and the workers' commits or patches. For
   patches, use `git apply --index -3`. Resolve conflicts by keeping both
   sides' intent; regenerate generated files rather than merging them. Take
   either side of a generated-doc conflict and run `make doc-generate` once at
   the end. Check that each cherry-pick finished before committing anything
   after it, and pass commit lists through `xargs`; zsh does not split an
   unquoted variable into words.
2. Build or probe the combined changes as needed. A three-way apply does not
   catch a caller using code another change deleted. For a language transition,
   follow [Capabilities](#capabilities) before applying callers that need it.
3. Review the combined authored diff for overlap, repeated checks, and
   leftover machinery.
4. Run `tools/land-dev "<bootstrap refresh message>"`. It integrates `dev`,
   regenerates docs, runs the final gate, commits generated changes when needed,
   and pushes only when the gate passes and the tree is clean. A rejected push
   requires integration and validation of the resulting tree.
5. A failed gate stops that attempt. Read its reported log path, fix the cause
   with focused checks, and then run `tools/land-dev` again. Each attempt keeps
   its own logs and a latest-attempt pointer. Preserve the failed tree and logs;
   do not discard generated changes or blindly rerun the full gate. A change to
   emitted C needs a second bootstrap round; `tools/land-dev` reruns the gate
   once when `stage-diff-0` fails, so no manual round is needed.

## Capabilities

A new native target, `meta` prototype, or compiler behavior can be implemented,
rebootstrapped, and adopted in one local branch and publication batch. Build the
capability and refresh bootstrap before compiling callers the old seed cannot
consume. Use focused probes or stage builds when they answer the transition's
current question. Give dependent workers the local capability commit as their
starting revision; no intervening gate or upstream landing is required.

The final published tip must rebuild from its shipped bootstrap and pass the
root publication checks. Intermediate private commits need not each satisfy
that property.

## Isolation

Each worker edits only its assigned isolated worktree. Worktrees share the
repository, so a worker can start from a local integration or capability
commit. If permissions prevent access to its assigned worktree, report the
failure to the orchestrator rather than switching to another worker's tree.
