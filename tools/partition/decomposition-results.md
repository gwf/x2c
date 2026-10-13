# Private-interface decomposition at dbdafacb

Compared source and graph snapshot at
`dbdafacb95dcc89cb2164787aa4a9bbfcb80d6ff`. Source hashes and authored same-file
edge weights match the sibling analysis. The reference's `analyze.py` assigns
source-section ranges and consolidates them by responsibility; it does not
infer graph communities. All five requested compiler results reproduce.

Counts below exclude synthetic top-level nodes, but those references remain
visible in the tool's extraction inspection. All runs request eight groups.

| File and method | Balance | Crossing pairs | Call sites | Static targets |
|---|---:|---:|---:|---:|
| compiler reference | n/a | 20 | 21 | 0 |
| compiler ordinary | 0 | 26 | 26 | 18 |
| compiler ordinary | .3 | 45 | 47 | 21 |
| compiler preserve-private | 0 | 14 | 14 | 0 |
| compiler preserve-private | .3 | 28 | 32 | 0 |
| macros ordinary | .3 | 126 | 127 | 83 |
| macros preserve-private | .3 | 3 | 3 | 0 |
| collect ordinary | .3 | 108 | 115 | 50 |
| collect preserve-private | .3 | 6 | 6 | 0 |

The old objective weights call sites and squared group sizes without treating
static targets differently. The new mode reuses `atoms` with caller/static-helper
constraints before that same heuristic. Public edges may cross boundaries.

## Legal components are not responsibilities

Compiler has 189 authored functions (86 public, 103 static), 74 components,
and a largest component of 51. At balance .3 the automatic sizes are
`56,27,21,17,17,17,17,17`. The semantic reference sizes are
`89,39,15,11,11,10,7,7`.

Automatic group 1 contains 56 parsing/token functions. Group 2 combines 23
production/transport functions, two source-location functions, and two
state/lifecycle functions. Group 3 combines 16 production/transport functions,
four path functions, and one names/pending-code function. Later groups mix
responsibilities further. For example, the seven literal-cache functions stay
in one group but share it with parsing, paths, locations, and pending code.
Fewer cuts or more equal sizes do not establish coherent responsibilities.

Macros has 355 authored functions and 30 components; the largest contains 320.
Its constrained sizes are `335,3,3,3,3,3,3,2`. Collect has 157 authored functions
and nine components; the largest contains 149. Its constrained sizes are
`150,1,1,1,1,1,1,1`. These graph results do not promise useful eight-way splits.

## Synthetic nodes and extraction coverage

The live UI retains top-level nodes. Compiler therefore has 190 nodes and 75
components; at balance .3 its sizes are `56,27,21,18,17,17,17,17`, still 32 call
sites and no static crossings. Its top-level node calls `List.var` eight times
and `String.var` eight times, and reports 30 indirect calls. It must not vanish
from extraction review.

Macros' top-level node calls `_forwarded_prefix_list` once and `String.var` 12
times. The static call joins its helper component. Collect's top-level node
calls `String.var` 16 times. Retaining that extra node changes heuristic seed
and assignment choices: its live eight-way split has four crossing call sites,
compared with six in the authored-only reproduction. These are different node
sets, explicitly reported, not different source snapshots.

The reference `probe-split.py`, `split-probe-manifest.json`, and
`split-probe/smoke-results.json` record a temporary eight-unit build, linked
without the original compiler object. Compiler, macros, and collect definition
dumps matched baseline. Public inline `Compiler.test` remained in the public
interface. These saved results were inspected, not rerun as a source refactor.
They are not a full regression proof. The manifest routes 13 private diagnostic
macros explicitly; call edges alone cannot perform that routing.

Callbacks, unresolved calls, private macros, private types, and file-local state
remain outside the resolved direct-call partition guarantee. Snapshot source
inspection exposes their code but does not automatically prove safe ownership.

Reproduce with `node tools/partition/tests/compare-decompositions.cjs` on the
matching snapshot. The reference fixture is deliberately revision-bound.
