# Partition

Partition helps build source-code responsibility groups from public operations,
subject to private dependency constraints. Graph views remain available for
exploring calls, groups, and tentative moves. It does not rewrite source files.

## Run

```sh
python3 tools/partition/generate.py
python3 tools/partition/serve.py
```

Open <http://127.0.0.1:8794/>. The server binds to localhost, disables caching,
and accepts `--port` and `--graph`. Generation builds stage 0, exports the
source graph through `commands/graph`, and atomically replaces ignored
`data/graph.json`. `--repo` and `--output` select another checkout or output.

## Build responsibilities

Open a file or group. The responsibility workspace is the main decomposition
workflow, with four steps:

1. Describe each public operation: its work, state owner, lifecycle, source
   section, and body/caller evidence. Source peek provides the snapshot source
   with line numbers and search; callers link to their own source.
2. Assign operations to named responsibilities with descriptions and evidence.
   Combine small responsibilities by a common task, state owner, or lifecycle.
   A combination records the affected component identities and concrete reason.
3. Reconcile private components. Same-file callers and static targets stay
   together, transitively. Recorded function-value references and explicit
   private declaration constraints also bind functions. Public calls do not.
   Conflicts show exact undirected helper paths. Merge the responsibilities
   under a broader name, or retain them as module members in one translation
   unit. Helpers never silently become public.
4. Review exact membership, static crossings, existing public crossings, and
   non-function constraints separately. Each function belongs to one proposed
   container. Results distinguish translation-unit candidates, module-member
   candidates, and unassigned/unresolved work. A helper-only component needs an
   execution/accessibility explanation and a responsibility attachment.

A proposal with unresolved work can be inspected in the graph. Accepting its
arrangement requires complete assignments and resolved recorded constraints.
Acceptance changes the tentative graph plan, not source code. An unresolved
constraint with no known consumer list conservatively affects the whole scope.

Use **Dependency constraints** to record private types, macros, file-local
state, and function-value references. Record source evidence before marking a
constraint reviewed or selecting functions that must stay together. The call
exporter does not supply exhaustive non-call dependencies; the workflow makes
those gaps explicit rather than claiming extraction safety.

**Export manifest** preserves operation records, stable function/component
identities, constraints, boundary decisions, and assignment/merge history.
Commit this JSON alongside the project being analyzed. **Import manifest**
requires the same snapshot and scope. The ordinary plan export also includes
responsibility workspaces. Browser storage retains work across reloads;
existing graph plans are preserved. Export remains necessary for versioning.

## Reviewed examples and reproduction

`web/responsibilities/*.x.json` contains reviewed public-operation evidence for
compiler.x, macros.x, and collect.x at snapshot `dbdafacb`. These descriptions
come from source bodies and caller evidence, not graph communities. Caller
bodies were inspected selectively, not exhaustively. Known private callbacks
are included; private declarations remain explicitly unresolved where their
ownership has not been established.

```sh
node tools/partition/prepare-responsibilities.cjs
node tools/partition/tests/compare-decompositions.cjs
```

The preparation command reproduces the versioned `*.manifest.json` files from
that evidence and the matching graph. It refuses another snapshot. Review and
update source evidence before preparing manifests for a new revision. The UI's
**Load reviewed source analysis** loads these editable examples only for their
complete original-file scopes.

The compiler eight-group fixture is a comparison, never an assignment input.
The comparison view shows the public operations and source behavior behind
current responsibilities alongside the reference destinations. `macros.x` and
`collect.x` retain large components with module members; no group count or size
balance is imposed. See [validation results](decomposition-results.md).

## Graph exploration

Group arrangement, Functions, and Function list preserve zoom, pan, weighted
calls, static/public colors, selection, source peek, and manual movement.
Outside caller groups remain on the periphery; their links fade in previews.
Group circles show function counts, edges show call-site weights, and arrows
run from blue to orange. Manual moves show cut changes and private-visibility
opportunities separately. Undo/redo applies to graph-plan changes.

Selecting a function highlights directed transitive same-original-file static
callees and reports external callers, shared helpers, and its anchor score:
`ln(1+external callers) * ln(1+static dependencies)`, normalized to 100. These
counts do not include missing indirect references. Source peek shows complete
snapshot files, not exact extracted function ranges. Edited group source-line
sizes remain estimates.

Automatic count/balance partitioning and cut/localization move suggestions
have been removed. Connectivity helps inspect a responsibility decision; it
does not supply one.

## Optional checks

```sh
node tools/partition/tests/check-responsibilities.cjs
node tools/partition/tests/compare-decompositions.cjs
node tools/partition/tests/check-engine.cjs
node tools/partition/tests/check-privacy.cjs
node tools/partition/tests/check-moves.cjs
node tools/partition/tests/check-anchors.cjs
node tools/partition/tests/check-boundary.cjs
node tools/partition/tests/check-layout.cjs
node tools/partition/tests/check-project-map.cjs
python3 tools/partition/tests/check-data.py
```

These focused checks do not add a recurring compiler gate. The browser uses
plain JavaScript and CSS without a build step or package dependencies.
