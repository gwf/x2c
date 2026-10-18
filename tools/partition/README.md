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

Generation exports the entry units that `tools/sources.py` lists. A module
unit is one file record, as in the compiler; its `members` hold the text of
its other files. Each function records the file that holds it (`p`) and its
storage tier (`v`): `static`, `module`, or `public`, as defined in the
[source graph datasets](../../commands/graph/README.md#export-datasets).
`s` marks a definition private to its unit, which is either private tier.
Source peek shows the file that holds the function.

## Build responsibilities

Open a file or group and select **Analyze source**. The local server uses the
installed, signed-in `codex` CLI to read the graph snapshot's source bodies,
comments, callers, and dependencies. It produces operation descriptions and
responsibility assignments; you do not need to fill in forms first.

Analysis opens the proposed graph arrangement directly. Reopening an analyzed
file also opens that arrangement. **Evidence and adjustments** provides optional
details without a sequence of workflow tabs. Inspect public operations,
attached helpers, shared components, and unresolved constraints. Rename or
combine responsibilities, edit assignments on demand, and use the graph to
inspect calls or move functions. Evidence and manifests remain available in a
collapsed disclosure. Reanalysis preserves an existing proposal until you
explicitly replace it.

Agent analysis runs read-only against temporary snapshot files. The existing
dependency engine checks the resulting manifest and keeps private components
intact. Conflicting responsibilities remain module members in one translation
unit. An incomplete agent response is reported as unfinished analysis, not as
homework for the user. Unresolved source dependencies remain visible; an agent
proposal is not an extraction proof.

This prototype runs one analysis at a time. The sidebar lists running, finished,
and failed analyses and links directly to each result. Reloading reconnects to
the server. Completed results are also retained in ignored data/analyses.json;
a server restart marks interrupted jobs unfinished instead of leaving them busy.
Proposals opened in the browser can be exported. The CLI uses its existing configured
model and account. Compiler and runtime sources are not edited.

## Reviewed examples

`web/responsibilities/*.x.json` contains reviewed public-operation evidence for
compiler.x, macros.x, and collect.x at snapshot `dbdafacb`, before those files
became module units. They load only against that snapshot. These descriptions
come from source bodies and caller evidence, not graph communities. Caller
bodies were inspected selectively, not exhaustively. Known private callbacks
are included; private declarations remain explicitly unresolved where their
ownership has not been established.

```sh
node tools/partition/prepare-responsibilities.cjs
```

The preparation command reproduces the versioned `*.manifest.json` files from
that evidence and the matching graph. It refuses another snapshot. Review and
update source evidence before preparing manifests for a new revision. The UI's
**Load reviewed source analysis** loads these editable examples for their
complete original-file scopes. From a previously split group, loading the
analysis opens the whole original file without changing existing groups.

The compiler eight-group fixture is a comparison, never an assignment input.
The comparison view shows the public operations and source behavior behind
current responsibilities alongside the reference destinations. `macros.x` and
`collect.x` retain large components with module members; no group count or size
balance is imposed. See [validation results](decomposition-results.md).

## Graph exploration

Group arrangement, Functions, and Function list preserve zoom, pan, weighted
calls, storage-tier colors, selection, source peek, and manual movement.
Outside caller groups remain on the periphery; their links fade in previews.
Group circles show function counts, edges show call-site weights, and arrows
run from blue to orange. Manual moves show cut changes and private-visibility
opportunities separately. A private target called across groups would need
public storage if the groups became separate units. A file static among them
would need only module storage if the groups stayed member files of one
module unit; the metrics and move results count those separately. Undo/redo
applies to graph-plan changes.

**Member files** draws the view's files by storage tier. File statics sit
inside their file, module functions on their file's border, and public
functions on the view's outer border. Lines aggregate calls between files. A
dashed ring marks storage wider than the exporter's `needed` tier. Below the
drawing, a matrix counts call sites between files, and a list gives every
definition with wider storage than needed.

Selecting a function highlights directed transitive same-file static
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
