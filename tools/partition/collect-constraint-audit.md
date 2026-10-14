# collect.x: constraint audit and responsibility arrangement

This audit applies to Partition snapshot `dbdafacb`, the source currently shown
in the explorer. It does not rewrite compiler source or claim a compiled extraction.
The reproducible assignment is `web/responsibilities/collect.audited.manifest.json`.

## What actually joins the code

| Evidence used | Largest private dependency component |
| --- | ---: |
| Resolved same-file static calls only | 149 functions |
| Calls plus the two shutdown callback references | 151 functions |
| All original additional constraints | 151 functions |
| Corrected type and individual state-access constraints | 151 functions |

The original 157-function displayed group combined that 151-function component
with six independent public operations assigned the same responsibilities.
The remaining node was a synthetic top-level record, not a useful extraction.
Removing speculative constraints does not disconnect the real private calls.
Those calls constrain separate translation units, not source-file module members.

## Corrections to the recorded constraints

- Shared helper summary: redundant. Use actual call edges rather than another
  union of public operations.
- Cache ownership: real private state, but the single bundle was too vague.
  Record individual accessor sets for each variable, including interface state
  that the original analysis omitted. Shutdown still connects several owners.
- Shutdown callbacks: real references and ordering. Order does not independently
  require co-location. Preserve `_process_cache -> _cache_shutdown` and
  `_interface_lisp -> _interface_shutdown` as function-value references.
- `Splice`: real private type. Include all direct consumers, not just a subset.
- `FileWalk`: real private type. `_bind_pending_inline_bodies` and
  `_publish_inline_dependencies` do not use it. The deferred-body array is a
  `Compiler` field, not private state owned by this source file.
- `Surface`: real private package state. Include all direct consumers.
- `Gathered` and `ColdConformances`: real private types within conformance work.
- Entry tuple representation and source order: real shared contracts, but an
  invented independent co-location requirement. Record them as contracts.
- Diagnostics: real static macros. They must move with their consumers or remain
  visible through the shared translation unit. They were not absent dependencies.
- Linked prelude and source-path contracts: real behavior; no independent union.
- Arbitrary source-defined effects: coverage limitation, not a placement veto.

## Useful source-file decomposition

All entries below are module-member candidates within the existing translation
unit. Each of the 158 graph records is assigned exactly once; entry storage also
owns the synthetic top-level record. Private symbols keep their visibility.

| Responsibility | Functions/records | Work |
| --- | ---: | --- |
| Collection | 41 | Walk and replay declarations in source order |
| Module assembly | 12 | Expand module members and preserve source locations |
| Package installation | 15 | Discover packages, choose exports, install declarations |
| Imported effects | 7 | Replay imports and compile-time definitions |
| Header publication | 13 | Determine declarations and types needed by generated headers |
| Conformance recording | 11 | Resolve and retain declared protocol results |
| Meta provider reuse | 9 | Check provider freshness, hashes, and binding names |
| Entry storage and interfaces | 50 | Retain entries and serialize/load their representation |

These assignments have source evidence in the manifest. Public operation
assignments take precedence over source position. The graph shows private
cross-member calls explicitly rather than silently turning helpers public.
The 50-record entry owner remains a substantial module; no balanced size claim
is made. It can be investigated further without hiding its current dependencies.

## First separate-compilation candidate: module assembly

`Compiler.module_source` and its 11 private helpers occupy lines 316-507.
They own `Splice`, assembled output, source markers, and module membership hashes.
There are only two outgoing same-file private-call pairs:

- `_member -> _canonical_path`, one call site at line 442.
- `_member -> _content_hash`, one call site at line 442.

`_canonical_path` is a pure wrapper around `real_path` with a spelling fallback
(lines 1265-1268). `_content_hash` formats the text hash (line 192).
Neither operation owns process-cache state. The same-file incoming caller is
`_walk_apart -> Compiler.module_source`, already a public entry point.
The five private module diagnostic macros are at lines 71-109.

A separate translation-unit extraction therefore needs explicit placement or
replacement of those two small pure operations, movement of `Splice` and the
five diagnostics, and normal include/declaration verification. It does not need
to make cache internals public. A module-member extraction avoids those interface
changes entirely. Neither extraction was performed or compiled in this tool audit.
