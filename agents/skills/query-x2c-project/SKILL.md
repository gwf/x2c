---
name: query-x2c-project
description: >-
  Answer project-wide x2c source questions using reusable graph snapshots:
  callers, paths, type dependencies, field accesses, structural AST matches,
  and changes between snapshots. Use for semantic code discovery and impact
  investigations. This skill does not authorize source edits.
---

# Query an x2c project

Use the compiler-backed snapshot to locate and explain relevant code. Read
[the snapshot command reference](../../../commands/graph/README.md#reusable-project-snapshots)
for exact CLI options, query fields, relationship kinds, and working examples.
The root `AGENTS.md` owns conversational style and delivery policy.

## Select the evidence

Identify the target/profile or explicit source-unit set that answers the
question. Module members belong to their entry unit. Different configurations
need separate snapshots; a missing source set is a coverage gap.

For current-tree questions, run `x2c graph status SNAPSHOT` first. Rebuild
explicitly when source membership or fingerprints changed. Saved-snapshot
questions can intentionally use old evidence; name the snapshot in the answer.
`snapshot` performs normal compiler analysis and compile-time execution.
`query`, `status`, and `diff` do not execute query code or rebuild source.

Keep generated snapshots and query files in `/tmp` or the task's permitted
scratch directory. Use `x2c graph snapshot OUTPUT` with ordinary build options
or explicit source files. Snapshot creation neither installs dependencies nor
builds application executables. Follow the ordinary project workflow if a
required dependency is unavailable.

## Find, follow, inspect

Find entities by name, kind, unit, or source text. Resolve ambiguous names with
returned IDs. Type aliases and aggregate tags are distinct entities, as are
same-named file-private declarations.

Traverse only the relationship kinds relevant to the question. Calls,
references, fields, representation requirements, and type exposure answer
different questions. Expand an edge into its occurrence evidence and inspect
its saved source before proposing a change.

For structural questions, inspect one representative `typed_ast`, test a
Match pattern against that entity, then broaden the selection. Compose shape
matching with binding, declared/resolved type, containment, or reachability
filters. Keep canonical AST syntax; do not substitute a text regex for a
binding-aware query.

Paginate when `truncated` is true. A first page is not a complete inventory.
Use `diff` after an explicit rebuild to identify changed signatures and
relationships. Inspect uncertain additions/removals rather than assuming a
rename or semantic equivalence.

## State the result precisely

A recorded path is a static relationship, not proof of runtime execution.
No recorded path is not proof of absence. Call out unresolved calls, missing
implementations, unlocated generated syntax, and other material coverage gaps.

Field and type edges do not establish ownership or arbitrary alias effects.
Use the existing specialized flow/lifetime commands when the question needs
those bounded analyses. A snapshot query alone does not prove that moving or
deleting code is safe.
