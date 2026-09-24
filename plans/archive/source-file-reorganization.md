# Source file reorganization

> Status: done
> Completed September 24, 2026 as `06c14139` on `dev`. Three function
> groups moved next to their callers. The experiment showed that moving
> functions between files is not a large lever for this codebase.

## Question

Can call-graph analysis find groups of functions that belong in a
different file, so that moving them lowers the number of calls between
files?

## Method

`tools/x2c-graph datasets` exported the resolved direct-call graph of the
hand-authored `src/` and `lib/` units at `fd2d5958`: 4,849 functions and
18,871 weighted edges. Calls into `lib/string.x`, `lib/list.x`,
`lib/common.x`, and `lib/array.x` were left out because nearly every unit
uses them. That leaves 9,062 cross-file calls.

The relocation search repeated these steps until no move helped:

1. Cluster each file's functions with Louvain community detection on the
   calls inside that file. Keep a cluster when its internal calls exceed
   its calls to the rest of the file.
2. For each cluster, compare its calls to another file with its calls to
   the rest of its own file.
3. Move the cluster when that lowers cross-file calls.

## Findings

Taken literally, the search collapses the code into the most-called
files. The fewest cross-file calls come from one file, so every step pulls
code toward shared services such as the token cursor in `src/compiler.x`
and `lib/buffer.x`. After 711 moves, `src/compiler.x` grew from 229 to 566
functions and five files were empty.

Two constraints made the result usable. Each call was weighted by one over
the number of files that call its callee, so shared services stop pulling.
`lib` code never moved into `src`, because `lib` is the shipped runtime.
With those rules and `lib/func.x` held fixed, the search found 153 moves of
485 functions, a projected 8.6% reduction (782 calls).

A mover script applied the moves, and a clean build tested every file
pair. 88 of the functions are macro expansions with no source text. Of 96
file pairs, 32 built. The 64 failures, by the calls each pair would have
saved on its own:

| Cause | Pairs | Calls |
|---|---|---|
| Include cycle or include order | 30 | 178 |
| Private helper or file-local data | 20 | 133 |
| Private type (`MatchLower`, `LispLower`) | 4 | 114 |
| Missing system header | 5 | 64 |
| Macro visibility | 5 | 50 |

Calls between files follow from shared types and the pass structure, not
from functions placed in the wrong file. Fixing every failure cause would
cap the gain near 6 to 8 percent.

An earlier proposal to split `src/expressions.x` and `src/macros.x` into
new units was dropped: each extraction adds cross-file calls, since the
calls across the cut start crossing a file boundary.

## Result

Three groups moved, saving about 26 cross-file calls:

- `Compiler.init_statements` from `src/compiler.x` to `src/generate.x`.
- `Compiler.meta_type_layout`, the `_meta_*_layout` helpers, and
  `Sym.is_bool_type` from `src/compiler.x` to `src/comptime.x`.
- `MatchMachine.open` and `MatchMachine.dispose` from
  `lib/match-machine.x` to `lib/match.x`, documented and listed as
  runtime-internal in `docs/library-api-tiers.txt`.

`File.write` and `File.write_repr` stayed in `lib/file.x`. The first
wraps `fwrite`, and the second is published `File` API.
`tools/gate-state.py ensure agent-pr-check` passed on the delivered tree.
