# Per-unit interface files replace the tracked symbol artifacts

> Status: done
> Approved 2026-09-14 and merged to main through PR #45 (3d4c14d) on
> 2026-09-15. Archived 2026-09-15.

## Context

Global declaration discovery depended on two tracked generated files:
`etc/symbols.xlisp`, an aggregate snapshot of the runtime dumped from
`lib/x2c.x` and loaded once per process as the implicit prelude, and
`etc/header-symbols.xlisp`, a per-header contribution cache keyed by file
path, content hash, a format version, the snapshot hash, and one absolute
gensym base. Both were inputs to stage 0 and outputs of stage 0, so the
build iterated (`stage0-settle`), an emission change needed two
publication rounds, a rebase left stale artifacts that made stage-0 timing
about 2x slow, and `precommit` carried `sym-check`, `hdr-sync`, and
`hdr-check`.

Every translated unit now writes its collected contribution beside its
generated C as `<stem>.xi`. The prelude is the runtime `x2c.xi` interface, produced by the
library batch of the stage that consumes it. Nothing tracked is both an
input and an output of a stage, so the convergence machinery, the artifact
hash checks, the sync tool, nine Make targets, and two CLI flags are gone.
Gary chose to remove the whole related public surface rather than keep
aliases. The x2c home discovered by the installer keys on
`etc/compiler-sdk.xlisp` instead of the snapshot.

## Design

- Interface: `(interface 1 "path" "hash" (parts...) (definitions...)
  (dependencies...))`, written by `interface_write` (`src/collect.x`) with
  the existing `snapshot_write_var` serializer and read whole by
  `_interface_read` through the bare Lisp reader. Parts keep the ordered
  declaration maps and include placeholders `_replay_cached` consumes, so
  last-write-wins merge order and once-per-unit include visiting are
  unchanged. Paths inside are home-relative when possible.
- Resolution order for a file's interface: the current `--out-dir`, its
  sibling that mirrors a home file's directory, the stage directory when the
  compiler runs from `<home>/builds/` or the home otherwise, then a package's
  `builds/` beside or above the source. A candidate is used only when its
  recorded path, source hash, included interfaces, and dependency hashes
  validate; otherwise the file is walked cold and cached for the process.
- The prelude entry is `lib/x2c.x`'s: the process cache, the runtime `x2c.xi` interface, or
  one cold walk per process (about 0.26 s). `x2c env prelude` prints the
  interface a compiler would replay.
- Cache entries install once. A unit's own walk after the prelude replay
  omits covered includes that add nothing, and that narrower entry must not
  replace the complete one the prelude walk produced.
- Anonymous aggregate identities are `(gensym "<file>" N)`, numbered per
  file, so no process-wide base exists. Emitted C never prints one.
- `builds/stage.mk` and `etc/x2c.mk` list the compiler and the runtime
  sources as translation prerequisites; depfiles list the replayed runtime
  sources, which the build-state hash already covers.
- Shipping: `etc/x2c-payload.py` copies `builds/0/lib/*.xi` into an
  installed home's `lib/`; `packages/tools/bundle.py` bundles a package's
  `builds/*.xi`.

## Validation

- `run-header-cache.sh`: warm replay byte-identical to a cold walk, merge
  order, gensym consumption, tampered-row liveness, stale-hash rejection,
  foreign-form tolerance, out-of-home includes, embedded-text and macro
  dependency invalidation, batch-versus-solo parity, prelude modes.
- `run-artifact-atomicity.sh`: repeatable interface bytes, no partial file
  after a blocked publication.
- `run-symbol-snapshot.sh`: prelude-versus-live parity, a home without
  runtime sources fails loudly, a home without interfaces walks cold to the
  same C.
- `run-cli-boundary.sh`, `run-protocol-boundaries.sh`, and the fixture
  suite retargeted; `tools/gate-state.py ensure agent-pr-check`.

## Plan review

Facts established elsewhere: `_file` establishes an entry's parts, hash,
definitions, and dependencies; `_replay_cached` establishes merge order;
`Build._state_dependencies` establishes that depfile prerequisites enter the
build hash. The interface reader validates the same hashes `_artifact_fetch`
validated, per file instead of per artifact.

Deleted: the snapshot writer and loader, the artifact header and line index,
`gensym_base` and `gensym_cursor`, the sync tool, the settle loop, nine Make
targets, and two CLI flags. Reused: the serializer, the bare reader, the
entry shape, the replay walk, the process cache, and the depfile writer. New:
one reader and one writer of a single-entry file, one candidate list, and one
`env` row. The file-scoped gensym tag replaces a process-wide integer with a
path and an integer. No new diagnostic; the interface write failure reuses
the `emit` diagnostic channel and is pinned by the atomicity probe.
