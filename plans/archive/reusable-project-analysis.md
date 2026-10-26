> Status: done
> Implemented 2026-10-26 through `41348efa`: persistent snapshots, function
> and type queries, structural matching, comparison, documentation, and skill.
> Focused acceptance and the complete graph suite passed. Publication uses
> the existing agent-pr-check gate on the integrated delivery tree.

# Reusable project analysis

## Result and boundaries

Extend the experimental `x2c graph` command with versioned, persistent
snapshots. Explicit full rebuilds use the existing project planner and compiler
frontend. Queries load saved analysis without parsing source or running meta
code. Preserve existing graph commands and TSV exports.

Support explicit source sets and a manifest-selected target/profile with its
dependency targets. Preserve configuration and linkage boundaries. Missing
dependencies are reported, not installed. Snapshot construction runs normal
compile-time code but does not build application executables.

Retain bound, macro-expanded ASTs, source text, origins, and semantic facts
before closing each unit. Export portable values, never live compiler pointers.
Publish only completed snapshots; failed rebuilds preserve previous contents.
Status checks freshness explicitly. Incompatible compiler identities require
rebuilding; older source snapshots remain queryable.

## Analysis and interface

Retain functions, named types, fields, globals, files, and units with qualified
identities. Keep occurrence evidence for calls, references, containment,
aliases, field value/pointer types, parameter/result/callback types, body type
uses, field reads/writes/mutations, representation uses, protocols, and delegates.
Distinguish declared from resolved types and unresolved from resolved edges.
Do not infer ownership from pointers or runtime reachability from call paths.

Add `snapshot OUTPUT`, `status SNAPSHOT`, `query SNAPSHOT QUERY_FILE`, and
`diff BEFORE AFTER`. Query files and replies use JSON; Match patterns and AST
views use canonical datum text. Support find, inspect, traverse, shortest path,
and structural match operations, boolean filters, explicit pagination, and
source-linked explanations. Name ambiguity returns candidates. Diff uses
qualified declaration identity rather than transient binding numbers.

Structural search composes ordinary Match patterns with binding, type,
containment, and reachability filters. An agent can test a query on one entity
before searching the whole snapshot. Retain origins but ignore their wrappers
for ordinary structural recognition. Do not add arbitrary query execution.

Deliver a skill for freshness checks, explicit rebuilding, investigation, and
coverage interpretation. Defer MCP, incremental updates, automatic edits,
lowered/generated-C analysis, and general alias/ownership proofs.

## Implementation and acceptance

1. Establish snapshot export, reload, project inputs, and publication.
2. Extract function/type relationships and occurrence evidence using existing
   binding, type, protocol, and source owners.
3. Add queries, structural matching, pagination, and comparison.
4. Document the interface and provide the agent skill and executable examples.
5. Review and fix the completed authored diff before publication validation.

Focused fixtures cover process-independent reload, same-named declarations,
target boundaries, paths and cycles, type relationships, mixed call/field
queries, representation dependencies, typed calls inside loops, differences,
source edits/deletions, failed rebuilds, and incompatible snapshots. Preserve
the existing graph suite. Use the existing publication gate, with no new gate.

Measure rebuild time, peak memory, snapshot size, and repeated query latency on
compiler, runtime, and command sources. Keep metrics separate; do not assert
improvement without a comparable baseline.

## Design review

The compiler remains the semantic owner. The new command retains and queries
its results; it does not introduce a parser, type resolver, graph database, or
live compiler service. Existing datum, Match, project, and frontend operations
supply the shared mechanisms. The key risk is preserving complete semantic
context across unit teardown; reload and identity fixtures exercise that
boundary before expanding queries.


## Implementation evidence

The command reference is `commands/graph/README.md`; the agent workflow is
`agents/skills/query-x2c-project/SKILL.md`. Acceptance lives in
`commands/graph/tests/snapshot.py` and `query-boundary.py`, called by the
existing graph suite. No new recurring gate was added.

Review corrections preserve complete unit ASTs, distinguish struct tags from
typedefs in comparison, retain effective target configurations, and exclude
indirect pointer stores and pointer-size operations from direct field/layout
claims. Source-file inspection reads retained text. Unchanged full rebuilds
compare without declaration or relationship differences.

### Measured workload

Measured on Apple M4 Max, arm64, at `41348efa`, on 2026-10-26. One explicit
analysis set contained 179 source units: 62 compiler, 69 runtime, and 48 command
files. Compiler/runtime entry units came from `tools/sources.sh --area src`
and `--area lib`, excluding generated `lib/x2c.x`. Command inputs were each
registered command's top-level `.x` files. Include paths were `.` and `src`.
The snapshot includes bound unit ASTs and declaration ASTs.

| Measurement | Result |
| --- | --- |
| Full rebuild, wall time | 380.63 s |
| Peak resident memory, `/usr/bin/time -l` | 4,872,454,144 bytes |
| Snapshot disk size | 499,103,270 bytes |
| Find, three fresh processes | 4.149, 4.098, 4.143 s; median 4.143 s |
| Transitive callees, three fresh processes | 7.692, 7.732, 7.691 s; median 7.692 s |
| Structural match, three fresh processes | 4.084, 4.092, 4.142 s; median 4.092 s |

All query measurements include loading the saved snapshot. Find selected
`Compiler.bind_syntax` (one entity). Traverse followed its `calls` closure
(3,598 entities, first ten returned). Match selected that function and used
`(expr ?type (call ?callee (args *args)))` (17 matches, first ten returned).
Results have explicit truncation. These are initial costs, not evidence of a
speed improvement. Queries currently load the entire datum snapshot; the
measured startup cost remains a limitation of this experimental CLI.

The raw local measurement directory was
`/private/var/folders/ys/92c9nxl16ds47h6mhvb9w_cm0000gt/T/x2c-analysis-final-s2rl59tr`.
It contains the exact input list, revision, time output, query JSON, and samples.
