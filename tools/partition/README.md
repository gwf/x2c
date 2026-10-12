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
- Group count ranges from one to 50 on the slider, limited by available
  functions and keep-together sets. Its pending value updates during dragging;
  the partition changes on release. Exact count can reach singletons, subject to keep-together sets.
  Size balance independently trades lower cut cost for more similar group sizes.
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
function is unused. Source peek is a placeholder showing identity: exact source
ranges and source navigation are not implemented. Edited-group source-line
counts are estimates. Plans propose file boundaries but do not apply them.
