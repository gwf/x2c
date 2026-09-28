# Raw-symbol translation of macros.x

> Status: active
> Reproduced on 2026-09-28 at dev `be226450` after `make build-safe`.
> Diagnosis and repair remain open; this record does not add a gate.

## Observed behavior

The explicit `make proof-raw-symbols` sweep finished in 111.96 seconds with
648 required sources, 409 classified exclusions, 647 successful comparisons,
and one failure: `src/macros.x` translated in CPP mode but failed in raw mode.
The complete Make command exited 2. Compiler and fixture source were unchanged
from the named dev revision during this investigation.

Raw translation reports that Compiler has no methods `parse_expression`,
`resolve_expression`, `parse_assignment`, and `parse_variable`. Both relative
and absolute source-path invocations reproduce the error, exiting 1. The
relative CPP-mode invocation exits 0. These checks used the same stage-0
compiler, source tree, and working directory.

## Reproduction

At the named revision, prepare the compiler with `make build-safe`, then run
from the repository root:

```sh
out=$(mktemp -d)
builds/0/x2c translate --out-dir "$out" src/macros.x
builds/0/x2c translate --cpp-symbols --out-dir "$out" src/macros.x
```

The first command should translate successfully, and both modes should
produce the same C/H under the existing sweep contract. Currently only the
second succeeds. The full sweep remains available through its existing
explicit target; do not exclude macros.x or rewrite expectations to hide
this failure.

## Evidence and next work

The same sweep failed on macros.x before publication of the workflow change.
A relative-path raw translation subsequently succeeded in 717 ms with the
post-gate compiler at `813a897d`. That was an isolated pass, not a green full
sweep. Current fresh-build reproduction establishes that the issue remains;
it does not establish whether bootstrap generation, interface/cache state,
or intervening compiler changes explain the differing results.

Logs in `/Users/gary/.codex/worktrees/d40d/x2c/debug/`:
`raw-symbol-followup.log`, `raw-symbol-relative.log`,
`raw-symbol-absolute.log`, and `raw-symbol-cpp.log`.

Diagnose the missing method declarations through the existing declaration
collection and interface owners. Compare fresh stage-0 and self-hosted
compilers on the same source and isolate relevant cache state before naming
a cause. Repair the existing owner and verify the reproducer and complete
sweep without changing their expected contract. Publication follows the
ordinary final-tree gate; no recurring sweep requirement is introduced here.

## Plan review

This records a reproduced translation failure, not an inferred root cause.
It reuses the existing sweep and ordinary compiler operations. No new helper,
validator, representation, language diagnostic, negative fixture, or gate is
proposed. Determine the smallest repair from the reproduction before editing
compiler code.
