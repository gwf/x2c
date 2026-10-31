# Async merged-diff review and gate repairs

> Status: reference
> Reviewed the private async branch after merging dev at `ffd915bd0`.
> Starting private revision: `38e89217b`. No push or shared-branch update.
> Two reproduced runtime defects remain publication blockers.

## Repairs and cleanup

- Cold collection copied generated x2c output but omitted the native stack
  source and minicoro header. The scratch tree now copies the same two files
  as the stage build. File-set and byte comparisons remain unchanged.
- Removed two redundant section comments, corrected the wrapped condition
  wait call, and combined duplicate Thread documentation. The four known
  lint violations are gone without changing the lint baseline.
- Updated active BLIS, Torch, and yyjson README examples to the selected
  Scope names. The dated Torch pilot remains a historical record.
- Added the short Scope API/layout migration note and reconciled stale
  strict-build status in the plan. Regenerated API and website text through
  `make doc-generate` after the Thread documentation correction.

## Reproduced runtime findings

### Lisp activation is shared across suspended tasks

`lib/lisp/evaluate.x` installs `lisp_active` around evaluation and restores
its prior value on exit. `Lisp.active()` exposes that pointer to native
callbacks. Task boundary exchange currently omits it.

The probe creates two Lisp sessions whose native callbacks wait on separate
Channels. A third task releases both callbacks. Both resumed callbacks see
the wrong active session:

```text
side=0 active_matches=0
side=1 active_matches=0
```

The executable exits 1. Interleaved evaluator exit can also leave the caller
with a session installed by a task. Proposed focused follow-up: a Lisp-owned
pointer exchange, saved in each TaskJob and installed at existing boundaries.
Fresh tasks start without a Lisp activation. Test both interleaved evaluations
and Task.run invoked from an outer Lisp callback.

### Recursive rendering is shared across suspended tasks

`lib/dispatch.x` keeps the active `RenderPath` chain in TLS. Array and Map
renderers enter that chain before invoking a custom child renderer. Task
boundary exchange currently omits it.

The probe runs two tasks rendering the same acyclic Array. Its custom child
renderer waits on a Channel during the first call. The second task reports
a false cycle while the first task is suspended:

```text
<array: 0x...>
[ item ]
```

The executable exits 1 because the results differ. Proposed focused follow-up:
a dispatch-owned pointer exchange at existing boundaries and an interleaved
custom-renderer regression test. Neither fix needs a new framework or allocator.

Both probes were independently reproduced with the merged worktree compiler.
Sources remain in `.context/async-tidy-review-20261031/`. Build each with
`builds/0/x2c build -O2 -o /tmp/PROBE PATH_TO_PROBE.x`, then run it.
Build and execution evidence is in `debug/async-tidy-{lisp,render}-probe-*`.
These findings are recorded in `unittest/STATUS.md`; runtime fixes are separate
from this pass's known gate repairs and mechanical cleanup.

## Coverage and remaining limits

Reviewed Task scheduling/shutdown, Channel registration and commitment,
Scope bindings, Context/Pool exchange, Error/Exception/Match state, native
stack management, relevant TLS, the region-analysis changes, and task-facing
tests, examples, documentation, and build integration. The source review did
not establish another defect in those paths. Generated output is checked
through the existing stage and documentation comparisons.

No broad runtime simplification or new architecture is proposed. Configured
stack sizes and unsupported-backend behavior still have temporary probe
evidence rather than durable task-suite cases. Non-macOS-arm64 execution,
exhaustive native ABI/hardening configurations, performance/retention
acceptance, and the newly reproduced suspension defects remain open.
Normal benchmark reruns remain deferred while that suite develops.

## Local validation

The known cold-collection and lint failures reproduced before repair. After
repair, the unchanged cold comparison passes all 475 C/H/.xi files and the
lint fixture/corpus checks pass without a baseline change.

The `make agent-pr-check` attempt passed precommit and its bootstrap/stage
comparisons, artifact atomicity, cold collection, verification, and documented
output checks. Verification reports 1,150 unit tests and 99,495 assertions,
plus 1,357 compiler fixtures and 2,999 artifacts. All 136 checked documentation
outputs match.

That full invocation exited nonzero for two component failures:

- `doc-check` found the stale Thread API paragraph changed by this cleanup.
  `make doc-generate` refreshed it. The generated diff adds the record's
  lifetime sentence; a subsequent `make doc-check` passes.
- `commands-check` failed in the REPL saved-instruction replay test because
  native compilation could not find `x2c.h`. No REPL source differs from dev.
  The focused terminal check and a complete subsequent `make commands-check`
  both pass without a REPL source change. The failure's cause is not established.

All component checks therefore have passing local evidence, but the single
full-gate invocation was not clean. Preserve that distinction and obtain a
clean final run after the runtime follow-ups. No publication receipt was
requested for this private-delivery worktree.

Full logs remain in `debug/async-tidy-agent-pr-check.log` and
`debug/agent-pr-check/`. Follow-up results are in
`debug/async-tidy-doc-check-after.log`,
`debug/async-tidy-repl-terminal-rerun.log`, and
`debug/async-tidy-commands-check-rerun.log`.
