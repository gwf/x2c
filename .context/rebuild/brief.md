# Rebuild spike: design brief

Research spike, 2026-09-26. Read-only with respect to src/, lib/, etc/,
docs/. Outputs live under .context/rebuild/. Nothing here is a decision;
the report at the end is advice to Gary.

## The question

If x2c's compiler and runtime were rebuilt from scratch, in x2c, using the
current compiler to bootstrap, what architecture and implementation would
produce a substantially smaller hand-authored source tree while keeping
every documented feature and staying close to current performance?

Current size (hand-authored, from .context/rebuild/map.md):

| tree | lines |
|---|---|
| src/ | 41,951 |
| lib/ | 35,878 |
| etc/ hand-authored (.x, .xmacro, non-generated .xlisp) | ~2,800 |
| total | ~80,400 |
| etc/builtin-macros.xlisp (generated from 684 lines of x2c) | 8,719 |

The measure that matters is hand-authored lines after redesign. Formatting,
comment stripping, and cosmetic compaction do not count. Generated
artifacts count only through the source that generates them.

## Constraints Gary set

1. Every feature documented in docs/src/reference/language.md and the
   library book is required. A feature may be proposed for dropping only
   with a justification and the lines it saves, listed separately. The
   acceptance suite is unittest/ (suites, fixtures, probes), examples/
   manifest.txt, the stage 0-3 self-host comparison, and the Lisp
   differential checker. Fixtures that pin diagnostic wording may change;
   fixtures that pin behavior may not.
2. Performance: any dimension (compile throughput, generated-code speed,
   runtime hot paths, build orchestration) may regress up to 2x, but only
   where the design names the payoff for that regression. A design carries
   a ledger: dimension, expected change, what it buys. Unexplained
   regressions are defects. The instruments are the build-cost score, the
   shootout, bm-all, and the translation CSV (agents/performance-checkpoints.md).
3. Language changes: none, except for the architect explicitly licensed to
   propose "very small" changes. A licensed change must let every existing
   program migrate mechanically (a script could rewrite it) and must not
   change the meaning of a program that still compiles.
4. Scope: src/, lib/, and the etc/ compile-time environment are rebuilt.
   commands/ (repl, lint, graph) and packages/ are consumers whose compiler
   surface must survive (map section 2.12); they are not rebuilt.
5. Bootstrap: the current compiler is stage 0 until the new one compiles
   itself; the new compiler must eventually self-host and pass the stage
   comparison.
6. Values: elegance, performance, clarity, conciseness, in that spirit.
   Safety and verification machinery is presumed performative unless it
   prevents wrong output, corrupted state, or an unsafe native crossing.
   Simple contracts over boilerplate processing. Trust facts the producing
   operation established.
7. Decisions already measured and declined (map section 6) are not
   re-proposed without a new argument; a design that contradicts one says
   why the measurement no longer applies.
8. The result is idiomatic x2c in the repository's own style
   (agents/x2c-coding-style-guide.md, docs/src/guide/idioms.md): match
   templates over canonical Lists, `Struct.method` operations, foreach,
   Var where dynamism is wanted, 79 columns, separate `else`. Beauty is a
   criterion beside size: fewer lines reached by density, golfing, or
   C-style code that the idioms would write differently do not count, and
   a component estimate anchored on a C library (chibicc, sds, stb_ds)
   must say how the idiomatic x2c version differs from that anchor.
   (Added 2026-09-26 after the greenfield round; the reconciliation and
   the report apply it, the area designs did not have it.)

## Gary's hypotheses (to prove or refute, not to assume)

- A large reduction "would likely mean that you figured out some way of
  doing a lot of the compiler work through meta and macros."
- "It could all come down to having a better Lisp implementation or a
  better compiler for it."

Facts bearing on both (verified in source):

- The built-in macros (foreach, scope, let, lock, class, auto, callback
  adapters) are already thin macro shells in etc/builtin-macros.xmacro
  whose algorithms are x2c meta functions in etc/builtin-macros.x, lowered
  by src/comptime.x (3,436 lines) into Lisp that lib/lisp.x (3,190 lines)
  interprets, with lib/machine.x + lib/lisp-machine.x (~1,000 lines) as a
  wordcode tier. The lowering expands 684 lines to 8,719 because it emits
  cons/quote chains rather than quasiquote.
- src/macros.x can dlopen native modules so compile-time code calls
  compiled functions (docs/src/guide/meta-functions.md "Native modules").
- examples/programs/literate-lisp.x implements the whole compile-time Lisp
  (reader, evaluator, standard vocabulary, REPL) in 1,000 lines and passes
  the differential checker against the production evaluator.
- Ast is `typedef List`; Lisp data, match patterns, AST, and runtime
  containers share Var/List. Match templates (`%(...)`) and List.match are
  ordinary runtime operations the compiler uses on itself.
- The compiler's own passes in src/ (resolve, convert, transform, cleanup,
  regions, emit) are hand-written walks; none is expressed as a macro or
  meta function.

## What a design must contain

Write the design to .context/rebuild/design-<key>.md (ASCII). Sections:

1. Thesis: the one idea that produces the reduction, in a paragraph.
2. Architecture: the components, the representation each owns, and the
   order of passes from source to C. Name what is a kernel operation
   (needs facts only the compiler has: binding, types, layout, lifetimes,
   emission order) and what is a macro or meta function over canonical
   syntax.
3. The compile-time execution model: how meta functions, `$(...)` Lisp,
   `$lisp.bind`, imports, native modules, hygiene, and the shared library
   session work; which of comptime.x, lisp.x, lisp-machine.x, machine.x,
   match-machine.x survive, are merged, or are replaced, and by what.
4. Feature coverage: walk map section 4 (the checklist). For each row say
   "kernel", "macro/meta", "runtime as today", "runtime redesigned", or
   "drop (justified)". Group rows; do not skip any.
5. Line ledger: a table of current lines by map subsystem (2.1-2.13) and
   the estimated lines after redesign, with the reasoning for each
   estimate. Total both columns. Estimates must be defended by a reference
   implementation of comparable scope (in this tree or elsewhere) or a
   concrete accounting of what is deleted.
6. Performance ledger: dimension, expected change, payoff, how it would be
   measured. Cover compile throughput (the build-cost score), macro
   expansion time, generated-code speed, and runtime hot paths (Var ops,
   Match, Scope/Pool, errors).
7. Bootstrap plan: how the new compiler is built by the old one, which
   parts must exist before self-hosting, and the order in which the
   current tree could be migrated if a rewrite were staged.
8. Language changes (licensed architect only): each change, its mechanical
   migration, and the lines it buys. Others: "none".
9. Risks and unknowns: what you could not verify, and what would refute
   the thesis.
10. Claims: a numbered list of the specific, checkable claims the design
    rests on (e.g. "regions.x's only hard-error consumer is the meta path",
    "quasiquote emission reduces builtin-macros.xlisp by ~10x"), each with
    file:line or a measurement. These go to adversarial verification.

Prose, tables where they compare. 300-600 lines. Cite file:line from the
map or from source you read. Where the map says a region was not read,
read it if your design depends on it.
