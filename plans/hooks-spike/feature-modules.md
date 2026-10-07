# Language features as modules

> Status: reference
> Research on private branch `gwf/hooks-spike`, 2026-10-07. Two read-only
> surveys classified every compiler language feature; their key claims were
> spot-checked against source. Line counts are approximate physical lines.

## Question

Can x2c language features live in single-purpose files that register one
lowering, so that a user include, a library file, and a compiler module use
the same shape? Which features are separable, and which are intertwined with
the compiler?

## Reference point

The built-in string switch (`builtin-string-switch.diff`) is purely
additive: one dispatch line in `Compiler._step_tag` and one 120-line block
that calls only shared services. It could be its own file.

## Classification

**A**: additive and self-contained, like string switch. **B**: self-contained
logic with a few named touch points elsewhere. **C**: intertwined with core
typing, binding, or control-flow analysis.

### Already extensions

These are keyword aliases or decorators that expand to ordinary syntax:
`foreach` (`keyword foreach $x2c.foreach`, etc/builtin-macros.x:16-27),
`class`, `$scope`, `$let`, `$lock`, `loop`, and everything in
lib/system-macros.x (`$switch`, `$time`, `$assert`, `$todo`,
`$unreachable`, `$dedent`). About 480 compiler lines plus 125 library lines.
`foreach` depends on four private primitives (`complete_iter_chain`,
`promote_string_literal`, function lookup, unique names); with those public,
it would be a pure library file.

### Separable with a seam

| Feature | Lines | Class | Touch points |
| --- | ---: | --- | --- |
| printf Var formats (transform.x:1208-1453) | 246 | A | one entry in `_call`; family table in expressions.x |
| Collection literals and literal order (transform.x:545-706) | 160 | A | public entry already called from cache.x |
| Cast, index, slice, return, var | 80 | A | thin routes into conversion services |
| Destructuring | 330 | B | pattern-keyed statement registration; function-entry pre-pass |
| raise | 200 | B | "never returns" fact; `runtime_literals` flag; `error.h` anchor |
| `$auto` and managed declarations | 110 | B | declaration position; `managed-init` node known in 5 places |
| String interpolation | 200 | B | tokenizer segment mode; literal cache |
| Runtime static locals | 320 | B | cleanup region participation |
| class defaults | 780 | B | collection-time declaration defaults service |
| Truthiness, getindex/setindex, dynamic operators | 470 | B | several handlers share the `op` arm; parent-before-child order |

### Core

| Feature | Lines | Why |
| --- | ---: | --- |
| Declarations, call arguments, assignment, comparison | 165 in transform plus initializers.x | implicit conversion rules of the language |
| defer | 320 | control-flow analysis over every transfer; the primitive other features reuse |
| try/catch/finally | 700 | regions, label ancestry, volatile preservation |
| match | 650 | binder scopes, cleanup barrier, its own emission |
| Lambdas | 550 plus callables.x | capture analysis inside identifier resolution |
| Protocols | 2,832 | operator typing depends on it |

Roughly: transform-phase feature code is 30% A, 59% B, 12% C; parse, bind,
and later phases hold about 480 lines A, 2,000 B, and more than 5,000 C.

## Seams a module system needs

Ranked by how many features need them:

1. **Typed node lowering.** The transform dispatch already declines by
   returning the node unchanged and re-normalizes a changed result. A module
   registry needs several handlers per kind and pattern-keyed registration.
   Used by string switch, collection literals, printf, raise, destructuring.
2. **Statement keyword at parse time.** Exists as `keyword` for identifiers;
   `hook` covers C keywords. Every core statement has two entries, the token
   parser (statements.x:91-119) and the constructed-form binder
   (parse.x:2862-2960); a module must register both, or the parser must
   always build syntax and then bind it.
3. **Declaration position.** `$auto`, destructuring, class, function hooks.
4. **Services for every module.** Unit support and file initialization,
   diagnostics at a node, include anchors (`error.h`, `exception.h`), and
   hygienic temporaries shared across quotations.
5. **Cleanup participation.** Barriers, regions, transfers. Needed by try,
   defer, match, switch, static locals. Hardest; `defer` is the published
   primitive features compose with instead.
6. **Identifier resolution.** `with` and lambda captures. Hardest; stays core.

## Roadmap shape

One module API, used in three places with the same source:

1. A user include prototypes an extension (project meta, out of process,
   about 1.3 M instructions and 0.17 ms per meta call).
2. Adoption moves the file into `lib/` (library meta, in process, about
   1.5 M instructions per use for `$switch`).
3. A hot or core feature moves into `src/` as a module behind one
   registration line (string switch built in: 6.55 M per use, below
   hand-written 7.75 M).

Rare constructs (string switch, printf formats, raise, foreach) tolerate
meta cost. Hot node kinds (operators, calls, declarations) stay compiled.

## Candidate experiments

1. **Typed-node hook.** `hook` at the transform phase; port string switch to
   it and add the node-diagnostic API for its label check.
2. **foreach as a library file.** Publish its four private primitives as SDK
   operations and measure.
3. **`$auto` through a declaration hook.** Delete the `managed-init` node
   kind and its five special cases.
4. **printf formats as its own file.** A pure refactor that tests whether a
   built-in moves out cleanly with no hooks.
