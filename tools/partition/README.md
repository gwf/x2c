# Partition

A local, experimental explorer for the x2c resolved call graph. Files start
as groups. Preview a split, accept it, split again, merge groups, or move
functions between them while watching the crossing-call cost. No source files
are rewritten.

## Run

From the repository root, with Python 3 and the normal x2c build prerequisites:

```sh
python3 tools/partition/generate.py
python3 tools/partition/serve.py
```

Open <http://127.0.0.1:8794/>. The server binds only to localhost. Use
`--port 8795` for another port, or `--graph /absolute/path/graph.json` to view
another exported snapshot. Stop with Ctrl-C.

Generation rebuilds stage 0 from the shipped bootstrap, builds the graph
command, exports every hand-authored `src/*.x` and `lib/*.x` unit (excluding
`lib/x2c.x`), then converts the TSVs to ignored `data/graph.json`. It replaces
the snapshot only after every command succeeds. `--repo` selects another x2c
checkout; `--output` selects another destination. Re-run generation and reload
the page after source changes. Graph extraction remains owned by
[`commands/graph`](../../commands/graph/README.md).

The browser has no package dependencies or build step. JavaScript and CSS
are served directly. Node.js is needed only for the optional checks below.

## Explore

- Project nodes represent current groups. Original-file circle area indicates
  physical source lines; edited groups use an explicitly labeled estimate
  apportioned by function count. Directed edges aggregate crossing call sites.
- Decomposed scopes and split previews start as circular group arrangements.
  Springs use aggregated call weights; repulsion separates groups. Hover traces
  connections. Workspace circle area is proportional to function count, printed
  inside each circle. Edges run from blue through purple to orange, with an
  orange arrowhead at the destination. Edge labels show exact call-site counts;
  width increases logarithmically with count. Call details lists every directed
  group pair and its exact count, largest first. Project edge counts appear on
  hover or keyboard focus. Labels count distinct callers
  outside each group, including siblings.
- Click a group to inspect its functions. Back returns to the arrangement.
  Tentative groups can be inspected without accepting the preview. Use Functions
  to expand all groups for moving functions, or Function list for keep-together
  selection. Shift-click project nodes or use
  the sidebar checkboxes to select groups for merging.
- Group count and size balance each have left/right buttons that change the
  displayed value by one and immediately update the preview. Group count ranges
  from one to 50; impossible counts report the available components. Size
  balance ranges from 0 (lower cut cost) to 100 (more similar group sizes),
  independently of group count.
- Collapsed arrangements keep outside caller groups in a fixed, scrollable
  peripheral rail. Only editable groups participate in the force layout. Rail
  counts and links count distinct callers; links marked `c` distinguish these from
  internal call-site weights. Outside callees are omitted.
- Suggest moves ranks up to twelve cut-reducing moves from the current view into
  connected groups. Each candidate moves a function or keep-together set, alone
  or with its strongest neighboring set. Review exact members, group sizes, cut
  change, and private boundaries before applying one move. Undo restores it.
  Initializers and moves that empty a group are excluded. These local candidates
  are design evidence, not proof of semantic suitability or global optimality.
- Localize functions ranks the same bounded moves by net private-visibility
  opportunities, then cut cost. Zero-cut and higher-cut moves remain eligible
  when visibility improves. Gains and losses name public functions whose last
  known outside caller disappears or whose first outside caller appears.
  These are candidates for source review, not automatic visibility edits:
  callback references, exported uses, and unresolved calls need checking.
- Manual and suggested moves show a result with before/after global cut,
  crossing call sites removed and introduced, visibility opportunities gained
  and lost, and remaining outside callers for each moved function. Existing
  private targets crossing boundaries are reported separately.
- Preview does not change the saved plan. Accept it before moving functions.
  Select a function, then drag it to another group, or use the inspector's
  destination selector. The function list supports keep-together sets.
- Static functions are amber; non-static functions are blue; initializers are
  gray. Public-node size reflects distinct consumers outside the current
  group. Static-node size reflects consumers inside the group. Size is not a
  measurement of function source length.
- The outside-caller panel groups callers by current partition membership. Each group
  connects to each group it calls; line weight and label count distinct caller
  functions, without multiplying callers that use several targets or call sites.
  Rows also show separate call-site totals. Split previews use their tentative memberships too. Click a group to inspect the exact
  callers and target functions. Per-group
  caller badges include sibling groups. Outside callees remain available in
  the inspector but are omitted from the graph.
- Scroll to zoom, drag the background to pan, and use Fit to restore the
  overview. Hover reveals names and connections.
- Undo and Redo cover accepted edits for the current page session. Restore
  original groups resets to source-file partitions and can be undone.

Accepted plans are stored in this browser, keyed by snapshot revision. Export
plan downloads JSON with function identities, groups, and keep-together sets.
There is currently no plan-import UI. Switching source revisions starts a new
plan; the old revision's stored plan remains in the browser. Dirty source checkouts receive a source-content suffix on the revision, so
changed source does not reuse a saved plan with stale numeric function IDs.

## Organization

| File                                    | Responsibility                                              |
| --------------------------------------- | ----------------------------------------------------------- |
| `generate.py`, `build-data.py`          | Export orchestration and TSV-to-JSON conversion             |
| `serve.py`                              | Local static server with a separate snapshot path           |
| `web/app.js`                            | State, actions, navigation, inspectors, storage, export     |
| `web/engine.js`                         | Partition heuristic, cut metrics, keep-together constraints |
| `web/decomposition.js` | Component grouping, reference comparison, snapshot source inspection |
| `web/boundary.js`                       | Exact edges crossing a view boundary                        |
| `web/graph-view.js`                     | Function graph, camera, drag interaction, caller panel      |
| `web/layout.js`, `web/layout-worker.js` | Function layout in a worker                                 |
| `web/project-map.js`                    | Weighted group graph layout and project interaction         |
| `web/index.html`, `web/style.css`       | Shell and styling                                           |

The partition heuristic tries several deterministic seeds and improves a
weighted cut plus a group-size balance penalty. It does not prove optimality.
API/helper keep-together constraints override cheaper cuts. Function layout
uses springs, repulsion, collision handling, and crossing refinement. Project
layout aggregates the global call graph by current group before applying
weighted attraction and repulsion.

## Optional checks

After generating the snapshot:

```sh
node tools/partition/tests/check-engine.cjs
node tools/partition/tests/check-moves.cjs
node tools/partition/tests/check-boundary.cjs
node tools/partition/tests/check-layout.cjs
node tools/partition/tests/check-project-map.cjs
python3 tools/partition/tests/check-data.py
```

The JavaScript checks accept `PARTITION_GRAPH=/absolute/path/graph.json`.
Tests combine small semantic fixtures with current-corpus checks, rather than
assuming one revision's function IDs or cut totals. They are optional and do
not add a recurring compiler publication gate.

For UI changes, also check project zoom/fit, function exploration, split
preview/accept/discard, movement, merge, undo, reset, caller inspection, and
export in a browser. The server disables asset caching.

## Limits

The snapshot is a resolved static call graph, not runtime traffic. Unresolved
and indirect calls are counted separately; missing callers do not prove a
function is unused. Source peek displays full snapshot source with line numbers
and name search. Search matches are not exact definition ranges. Edited-group source-line
counts are estimates. Plans propose file boundaries but do not apply them.

### File anchoring

Selecting a function highlights its directed, transitive same-file static
dependencies in green, while retaining immediate caller/callee context. The
inspector lists every dependency and marks helpers with callers outside the
root plus dependency set as shared. Show all dependency groups includes groups
containing helpers moved outside the current view.

The score is `ln(1 + E) * ln(1 + D)`, normalized to 100 at the snapshot maximum.
E counts distinct callers from other original files. D counts reachable static
functions in the same original file, traversing static callees only. Cycles and
shared paths count once; the selected function does not count itself. The score
stays tied to original files when tentative groups change. Unresolved and
indirect calls remain outside this estimate of attachment.

Optional focused check: `node tools/partition/tests/check-anchors.cjs`.

## Preserve private interfaces

Split previews enable this mode by default. Every same-file caller of a static
helper joins that helper's indivisible component, transitively, including
synthetic top-level callers. Calls to existing public functions do not join
components. Explicit keep-together sets are also respected. Size balance is
optional and off by default; it cannot break a component. A requested count
above the component count reports the limit and previews the achievable count.
Existing cross-group private calls remain visible; splitting one group does not
repair a helper already moved elsewhere.

Open **Inspect privacy components** in the group inspector. Expand components
to read public/static membership in source order. Open a function for its full
snapshot source, including section comments, private macros, types, and state.
Select components and give their combined group a name. Ordinary group merging,
renaming, and undo remain available. Components do not infer responsibilities.

**Inspect membership and crossings** separates static and public crossings,
shows concrete caller/callee pairs and call-site counts, and reports synthetic
top-level references separately. It also reports unresolved and indirect calls.
Zero static crossings does not establish source extractability.

**Compare source-informed reference** loads the eight compiler responsibility
groups from `web/fixtures/compiler-responsibilities.json`, only when the
snapshot's `src/compiler.x` matches the fixture's `sha256`. It lists all 189 authored members and source-section evidence
and uses the same crossing metrics as automatic proposals. Top-level references
are reported but the synthetic node is not assigned to the eight groups. This
fixture does not guide the automatic algorithm or prescribe other files' counts.

See [reproduced results](decomposition-results.md). Optional checks:

```sh
node tools/partition/tests/check-privacy.cjs
node tools/partition/tests/compare-decompositions.cjs
```
