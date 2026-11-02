# Helper-cache path identity correction

> Status: reference - implemented and validated locally.
> Recorded 2026-10-31. Source baseline: 5cef9448b.
> Normal benchmarks and all pushes remain on hold.
> Published to `dev` in `255de641f` on 2026-10-31 (noted 2026-11-02).
> The hold and no-push statements in this record are historical.

## Cause and smallest correction

The helper-loop guard compared Path.absolute(input), which resolves symbolic
links, against the configured cache-root spelling. An absolute symlink alias
or a relative cache root could therefore fail to identify the compiler's own
support unit. If that unit exposes a meta provider, translation can attempt
to build a helper for the helper itself and wait on the support lock already
held by its parent. A warm support object can hide the failure.

The guard now applies the existing Path.absolute operation to the cache root
in that same comparison. No cache-root accessor, cache key, directory policy,
lock handling, retry, production timeout, or public API changed. Path.absolute
already handles missing trailing components and resolves existing symbolic
links. It adds one root-path normalization to single-input support checks
when a cache root is configured. No timing claim is made.

## Focused regression

The existing run-meta-cache-key.sh installed-runtime fixture adds a harmless
meta body to the copied helper loop. This forces recursive discovery if the
loop is mistaken for project input, without editing shipped runtime source.
The new cases use separate cold absolute-symlink and relative-symlink cache
roots; the relative case also includes a trailing dot component.

Each translation must complete, emit the expected meta result, and produce a
support object. An external 20-second process-group watchdog prevents a
regression from hanging the test run and terminates only that case's group.
This is test cleanup; compiler timeout and locking behavior are unchanged.
No new recurring gate was added.

Before the fix, the exact extended harness fails at its external bound.
Separate cold probes confirm both absolute and relative aliases time out,
while the canonical path completes. After the fix, the entire cache-key
harness passes, including both new cases.

## Validation and coverage

The full local make agent-pr-check passes on macOS arm64, including bootstrap
refresh/recovery, strict self-host comparisons, 1,158 unit tests and 99,595
assertions, 1,357 compiler fixtures and 2,999 artifacts, documentation, and all
command checks. Existing meta-helper recovery/timeout, transport, source-kind,
and cache-key probes pass. No expectations were weakened.

The regenerated bootstrap/src/meta-project.c contains the matching guard call
and generated Error-site line-number shifts only. The authored and generated
diffs were reviewed and pass git diff --check.

An additional Linux run could not start because Docker Desktop is manually
paused. It was left paused. No Linux result is claimed for this follow-up;
there are no runtime-library changes requiring a new sanitizer run.

Evidence is retained in debug/async-cache-path-*. The full gate log is
`debug/async-cache-path-agent-pr-check.log`; before/after focused logs are
`debug/async-cache-path-regression-{before,after}.log`. Individual cold-probe
statuses are in `debug/async-cache-path-loop-cold-before.json`. All processes
started by the timed-out cases were terminated through their own groups.

## Delivery boundary

Everything remains local. This closes the observed cache-path deadlock; it
does not lift the dev/main validation hold, accept the remaining memory
tradeoff, resume normal benchmarks, or authorize a push.
