# Private async branch integration with current dev

> Status: reference - merged locally; combined review complete.
> Recorded 2026-10-31. Normal benchmarks remain on hold. No pushes authorized.

## Revisions and merge

Starting private head: f721a6ed02680322d71d9fda505d31dc9d5eb310.
Fetched origin/dev: b627bb039dfe477dd16e4cd1f8a87972bf86734a.
Merge: e8640be3c49cf78c2e37f43efa6e874b5a5645e9.
The merge has those two revisions as parents and required no conflict repair.
Nine upstream commits were integrated into codex/async-task-prototype.
The session remains individual/private. Dev and main were not advanced.

Incoming changes cover benchmark implementations, reference/calibration
records, benchmark tooling, related documentation, and the explicitly invoked
bm-c2x2c Make target. There are no incoming compiler, runtime, bootstrap,
native build-rule, or unit-test changes. Those files match the starting
private head exactly after the merge.

## Combined review

At the merge revision, the private diff against the fetched dev tip contains
215 files.
Read-only review covered the following authored changes and their consumers:

- Task startup, partial failure, completion, cancellation, and shutdown;
  Channel wait registration and commitment ordering; borrowed-owner lifetimes.
- Stable Scope slots and the selected representation/API changes; Context,
  Pool, Error, Exception, Match, Lisp, and rendering activation exchanges.
- Native stack storage, mapped job arrays, ASan boundaries, and the NaN,
  long-double padding, and helper-cache path fixes.
- Compiler region-summary production/replay, pointer-field provenance, the
  ordinary/audit/meta boundary, and graph contract consumers.
- Native source/header copy and archive rules, sanitizer source inclusion,
  test/probe registration, the task service example, and API/release/migration
  documentation.

The incoming x2c fannkuchredux and knucleotide sources were inspected for
Scope migration and native-thread borrowing compatibility. Both translate
and compile against the merged runtime. Their programs were not executed.
The ten optional-package files in the private diff contain only the exact
Scope.retain/release to Scope.open/close rename; no package behavior was changed.
The incoming Makefile change adds no benchmark dependency to the gates.

No concrete integration defect was found and no code correction was needed.
This is a bounded integration review, not an exhaustive vendor-assembly or
platform-hardening audit. Foreign-language benchmark implementations and
calibration figures were not independently re-audited or measured. Imported
performance records retain their upstream provenance; they are not performance
evidence for this private branch. Optional third-party package builds and the
previous four-platform sanitizer campaign were not repeated. Compiler/runtime
source is unchanged by this merge, so its existing native validation remains
applicable to those unchanged paths.

## Checks

The graph certification suite passes independently of the review workers.
All five shootout metadata/unit tests pass; they use fixtures and mocks rather
than benchmark workloads. The c2x2c benchmark command's help path and the
bench-directory shell syntax check pass. The two incoming x2c benchmark
programs pass compile-only checks.

The full local make agent-pr-check passes on the merged code tree. Bootstrap
refresh, safe rebuild, self-host comparisons, documentation checks, cold
collection checks, verification, and command checks all pass. Verification
includes 1,357 compiler fixtures (2,999 artifacts) and 1,158 unit tests
(99,595 assertions), with no failures or skips. No new recurring gate was added.

Evidence is retained in debug/async-dev-integration-*. Starting/fetched/shared
branch revisions and the merge revision are stated above and also kept in
the workspace-local, untracked `.context/async-dev-integration-20261031.json`. Read-only review workers also
ran focused region fixtures; the full gate independently checks those fixture
expectations. Graph certification was repeated by the primary session.

## Delivery boundary

Only the private branch advances. Normal benchmark reruns, performance and
remaining retention acceptance, dev/main advancement, and all pushes remain
held. Successful integration and correctness checks do not authorize publication.
