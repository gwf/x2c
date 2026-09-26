# Rebuilding x2c in x2c: research spike

> Status: reference - research only, 2026-09-26. No source changed. The
> supporting map, designs, ledger, and brief are under `.context/rebuild/`
> on branch `gwf/friendly-thompson-7a17so`. Answers Gary's seven questions
> and specifies the auto-research task; the decisions it leaves open are
> listed under "Decisions for Gary".

## The question

If the compiler (`src/`) and runtime (`lib/`, the `etc/` compile-time
environment) were rebuilt from scratch in x2c, bootstrapped by the current
compiler, what architecture would make the hand-authored tree substantially
smaller while keeping every documented feature, staying within a factor of
two on any performance dimension where the payoff is named, and remaining
idiomatic, self-contained x2c in the repository's own style?

Today: `src/` 41,950 lines, `lib/` 35,878, `etc/` hand-authored 2,585,
about 80,400 in all, plus the generated `etc/builtin-macros.xlisp` at
8,719 lines.

## How the answer was produced

A subsystem map (`.context/rebuild/map.md`, 16 readers, one section per
subsystem, a complete feature checklist, the measured declines from
`plans/`). Five architects designed from distinct stances (Lisp-first,
kernel plus macros, same-pipeline consolidation, licensed language changes,
fewest passes), three judges scored them, one synthesis merged them
(`design-*.md`, `design-synthesis.md`). Its 23 claims went to refuters
(3 refuted, 12 partly, 8 held; none moved a line total by more than its
own precision). Five more architects then estimated each area from scratch
rather than by subtraction (`design2-*.md`), and a reconciliation produced
one ledger with three numbers and ranked experiments (`ledger.md`). Three
experiments ran on this branch with patched compilers in worktrees; their
numbers are below. Everything cited was read in current `dev`.

## Answers

**1. What would change.** The representation stays: `Ast` is `List`,
`Type` is `List`, patterns, templates, Lisp data, and runtime containers
share `Var`/`List`, and every construct lowers to C through one backend.
What goes is the second compiler hiding inside the first. Today a `meta`
x2c function runs at compile time because `src/comptime.x` (3,436 lines)
translates its body to Lisp, `etc/comptime.xlisp` re-implements C
semantics for that Lisp, `lib/lisp.x`'s AUTO tier and `lib/lisp-machine.x`
word-compile it to win back speed, and the compiler's own built-in macro
algorithms ship as a 12.7x generated Lisp artifact loaded by every process.
The native path already exists: `meta native` and bodyless `meta`
prototypes make a compiled function available to compile-time code, and
`--kind meta-module` builds and `--native-module` loads such code. What
the rebuild changes is that this becomes the only path. Every bodied
`meta` function is compiled by the C backend like any other function:
linked into the compiler when it ships with it (`foreach`, `class`,
`scope`, callback adapters, autodiff, the tag ledger), and built once
into a content-hashed module and loaded through that native-module path,
automatically, when a user defines it. The one new mechanism is that
automatic staging step; everything else is deletion. Lisp stays as the documented
feature (`$(...)`, imports, `defmacro`, `$lisp.bind`) on a reader and
tree-walking evaluator of about 2,000 lines with a tail-call trampoline;
the wordcode tier, the lowering, its runtime, and the generated artifacts
go. After that the compiler is one lowering walk with a per-node fixed
point (transform, lambda lifting, and cleanup as one descent), symbol
scopes as frames rather than copied transactions, one top-level classifier
with a skip-body mode instead of two dispatch loops, protocol resolution as
ranked clauses, conversions as an ordered rule list, and no private emitter
node kinds. The runtime keeps its value model and gets Array and Map as
instantiations of the typed generic families, one error record and frame
chain instead of three, and one value-transfer walk instead of five copies.

**2. Do small language changes alter it.** One does, and it is the change
above: today `x2c_comptime_lower` and the documented compile-time subset
are the specification of compile-time x2c, so the lowering cannot go while
they stand. Withdrawing that operation (three callers, all generators) and
turning the subset's rejection table into acceptances is worth about 5,300
lines; every program that compiles today keeps its meaning, and the
subset's 18 `comptime-declines-*` fixtures become acceptances. Retiring
the legacy macro body forms is free (35 lines, fixtures only). Every other
syntax-level candidate (dropping generic selection, mixed declaration
rows, a collection-literal form, the two-file output model) buys tens of
lines or has no mechanical migration and was declined with its worth
stated (`design-language.md`).

**3. A design that leans into the meta and macro duality.** The duality is
already the right one: a macro is a hygienic List template over canonical
syntax expanded by `match` and `replace`, a meta function is x2c over
those Lists, and the compiler walks its own AST with the same `match`
templates. What is not Lisp-like is that meta x2c is re-interpreted by a
second compiler; the Lisp property worth having, that the language at
macro time is the language itself with `eval` at hand, is obtained here by
`eval` being the compiler plus `dlopen`. The hypothesis that a large
reduction comes from doing more compiler work through macros was tested by
two designs and refuted: every pass in `src/` is already a
match-and-template walk, so moving one behind the macro boundary relocates
its lines, and the passes that stay are the ones that need facts only the
compiler has (binding identity, types, layout, lifetimes, emission order).
The hypothesis that it comes down to a better Lisp implementation or
compiler held in one form: the better compiler for compile-time x2c is the
x2c compiler.

**4. Unnecessary abstractions.** Confirmed in source: the second backend
and its runtime (`C.true?`, `C.conv`, peek/poke over compile-time bytes);
the AUTO tier with speculative pre-expansion and machine slots; the Lisp
half of a machine only Match needs; the generated artifact and its
generator; the shared-session lifecycle flags and a restart-by-exception
for a parent session that can be built eagerly; a hand table restating
157 `meta` prototypes; a per-round unit re-walk plus a memo to make it
cheap; two after-the-fact cache-id walks; three recursive-mutex blocks,
four typedef walkers, two top-level dispatchers, six adapter memos; hand
public layers over the generated Array and Map families; three regions
per error record. Equally important is what reading showed is not one:
`regions.x` (one analyzer with three entries, and its meta error guards the
compiler's own memory), the native-meta inventory, the Match admission
memos (measured 2.35x), the two serializations (layers), and the recursive
mutexes where reentrancy is documented. The initial survey's largest
"duplication" rows evaporated on reading; the tree is mostly features
implemented once.

**5. Code quality over safety.** Kept because it prevents wrong output,
corrupted state, or an unsafe crossing: compile-time-only inference, the
meta region error, the module stamp, the native-meta lifetime certifier,
`volatile` across `sigsetjmp`, expansion guards, hygiene. Dropped as
performative: the subset's rejection table and fixtures, the
Lisp-boundary argument checks in `compiler-sdk.xlisp`, the `<lisp-late>`
restart, the AUTO transparency API, the call budget for native bodies,
`ScopeStats` fields with no reader, capacity fences that pin wordcode
limits. No origin tracking and no second validator anywhere.

**6. The auto-research task.** Specified below.

**7. How the pieces interact in the new design.** C is substrate and
target. `Var`/`List` is the one representation for AST, patterns,
templates, Lisp data, and containers, so a meta function, a macro
template, and the compiler's passes compute over the same values with the
same `match`. A macro is a template with hygiene, expanded at every syntax
position by match and replace and bound like hand-written code. A meta
function is x2c over those Lists, compiled to C, linked or staged, called
through a `Func`; it asks the compiler questions through the `x2c_*`
operations and answers with syntax the binder accepts by structure. Lisp
is the glue notation and evaluator for `$(...)`, `$lisp.bind`, imports,
and template splices, binding natives through one generated table and
checked against the reference interpreter. The word machine serves Match
only, the one place where compile-then-interpret was measured to pay.

## The numbers

Three estimates on the 80,404 base (`ledger.md` section 6):

| estimate | lines | change | assumes |
|---|---:|---:|---|
| verified-subtractive | ~73,150 | -9% | the language change licensed, the staging prototype (step 1 below) working, AUTO off (measured 5-11%), REPL latency accepted; without the language change the ceiling is ~77,700 (-3.4%) |
| greenfield-central | ~67,700 | -16% | the above plus every named fold with a file:line, Array/Map as family instantiations, the one-Pool error record and a frame chain that survives its prototype, frames for transactions, one classifier, one installer; unnamed folds at half; no comment compaction; no Match trade; 66,500 with autodiff moved to `packages/` |
| greenfield-with-every-trade | ~58,500 | -27% | the five area designs as written, every rope trade taken and measured inside its own bound, every unnamed fold realized |

By subsystem (current / credible / all trades): front end 5,341 / 4,950 /
4,450; syntax 6,618 / 5,880 / 4,930; macros and comptime 8,818 / 5,330 /
5,283; Lisp 5,338 / 3,200 / 2,958; transforms 5,542 / 5,150 / 4,470;
backend 4,141 / 3,650 / 3,617; driver 6,045 / 5,770 / 5,223; values
11,454 / 10,000 / 8,704; match 5,232 / 4,570 / 2,329; infrastructure
7,638 / 6,400 / 5,887; services 4,953 / 4,440 / 3,242; types and
`compiler.x` 7,492 / 6,700 / 5,890; other 1,792 / 1,640 / 1,576.

The survivors the designs list at the floor total about 36,000 lines, so
the floor under these designs is 55,000-58,000. The credible estimate sits
10,000 above it because half the difference is unmeasured trades and half
is folds nobody has written. Two caveats on the greenfield numbers: some
components were anchored on C libraries (chibicc, sds, stb_ds) as size
references, and sds is a mutable string buffer while x2c Strings are
immutable values, so those anchors bound the problem, not the idiomatic
x2c solution; and no design proposes adopting any library.

## Experiments run on this branch

Patched compilers were built in worktrees (`make build-safe`, about 70 s
here) and timed translating their own trees, `ulimit -s 65536`, box idle.
Generated C was byte-identical to the baseline for every unpatched source.

| variant | seven benchmark sources (5 samples) | all `lib/` | all `src/` |
|---|---:|---:|---:|
| baseline | 20.5 s | 114.6 s | 97.3 s |
| A: Lisp evaluator only, no wordcode tier | 22.9 s (1.11x) | 120.0 s (1.05x) | 105.1 s (1.08x) |
| B: reference recursive matcher, no compiled plans | 40.7 s (1.98x) | 222.3 s (1.94x) | 183.8 s (1.89x) |
| A and B | 42.5 s (2.07x) | 227.4 s (1.98x) | 192.9 s (1.98x) |

A decides the wordcode-tier trade: 5-11% on translation today, less once
meta code runs natively, against 2,070 hand lines plus 995 of tests.
Take it. Two facts came with it: the evaluator has no tail calls, so
without the machine a recursive native-table walk in `lib/lisp.x` exceeds
the 1,024 call depth and `lib/lisp.x` itself cannot be translated; the
rebuild's evaluator needs a trampoline (about 60 lines) and the depth
limit becomes a stack limit. The lisp suite passes at a 64 MB stack.

B decides the naive Match trade: the 445-line reference engine doubles
translation, at the edge of the rope, so the trade is dead as proposed;
the engines design's journaled, span-borrowing engine with fused loops
(`design2-engines.md`) is a different engine whose estimate (+4 to +12%)
is unproven until it exists. Matching is about half of translation time,
which is itself a finding: the compiler's cost is dominated by `List.match`
over its own AST and by `Pool_lookup` (the last profile put allocation at
about 30% of samples), not by the number of passes. B also exposed a
latent lifetime bug: a call-site plan retains its normalized pattern in a
pool that is later released; harmless today because only the compiler
reads it once, queued as a task.

E1 was misframed and is recorded as such. It moved the row helpers of
`lib/var-tags.xmacro` into a compiled compiler unit and measured
translation: parity (`lib/` in one process 11.6 s baseline, 11.7 s probe;
the seven-file set 20.1 s and 20.0 s; the two units that import the
ledger 3% faster). The plan-archive figure it was meant to answer (3.4x
slower) was about meta x2c lowered to Lisp, not about native code, so E1
tested nothing in dispute; native execution was never the question. What
it did show is the cost of the linked route today: spelling the helpers
`meta native` inside the imported `.xmacro` binds nothing, because an
import emits no C and the compiler binds only what it already links, so
the helpers became a new unit `src/var-tag-rows.x` (173 lines), an
include and a filter change in `src/macros.x`, twelve bodyless prototypes
in the `.xmacro`, and a bootstrap refresh between two builds. The
rebuild's "linked when shipped" is that route made routine. One
unexplained difference surfaced once in a warm output directory
(`tokenizer.c` with `tok == error_at` for `Token_equal(tok, error_at)`)
and did not reproduce in 72 further translations; it is noted, not
resolved.

The staging cost, the design's one new mechanism, measured with the
existing path: `x2c build --kind meta-module` on a one-function module
takes 2.6 s here (three runs), almost all of it fixed process cost
(startup, prelude collection, `cc`), against about a millisecond to lower
the same function to Lisp today. It is paid once per edit of a meta group
and cached, so ordinary builds barely see it; the REPL would pay it per
submission that defines meta code. A 118-function group could not be
built as a module without the design's own staging logic, because the
functions call each other at compile time during the module's own
translation, which is the first thing that logic has to handle.

## The auto-research task

Goal: implement x2c in x2c along the architecture above, dropping only
features whose sole consumer is the deleted engine, keeping performance
within the bounds below, and reducing hand-authored lines through
redesign. Reordering, formatting, comment compaction, and density do not
count; a run that reaches a number that way has not done the job.

Acceptance, every run: `make verify` (58 suites); `make verify-fixtures`
with the 18 `comptime-declines-*` expectations and any `.diagnostics`
that mention lowering allowed to change, and every `.c`, `.h`, `.stdout`,
`.status` fixture held; `examples/manifest.txt`; the stage 0-3 comparison;
`x2c script examples/programs/check-reference-lisp --build` with
`showcase.xlisp`, `init-core`, and `lisp-values` as inputs; the REPL,
native-module, package, sanitizer, and CLI-boundary probes; `git diff
--check`; `tools/gate-state.py ensure agent-pr-check` before any delivery.

Metrics and bounds: hand-authored lines in `src/`, `lib/`, `etc/` (the
generated `.xlisp` files count only through their source); build-cost
score within +3% clean and at or below baseline steady state; `lib/` and
`src/` translation wall within 1.10x of the re-measured baseline for any
single step and 1.0x at the end; bm-all Lisp rows at or below 1.5x;
generated-code speed unchanged on the shootout; cold `verify-fixtures`
within +20 s; REPL latency reported. Beside the numbers, three gates a
line count cannot express: the result compiles and runs with a C compiler
and libc and nothing else, the same as today (a new external dependency is
a failed run); `commands/lint` and the style guide pass; and a review
answers "would this be written this way here" against
`agents/x2c-coding-style-guide.md` and `docs/src/guide/idioms.md`, with
match templates, `foreach`, `Struct.method` operations, and `Var` where
dynamism is wanted. A run that trades those for lines fails.

Ordering (each step lands green on its own, in this order, each with its
measurement from `ledger.md` section 4):

1. The staging prototype: stage one user unit's bodied `meta` group
   (functions that call each other at compile time, `meta static` values,
   a raise reaching the call site) into a module and load it, on the
   existing native-module path, without touching the lowering. Measure
   the per-edit cost and REPL latency. If a group cannot be staged
   without the lowering's help, stop: the design reduces to
   consolidation.
2. Native meta execution: `src/stage.x` replaces `src/comptime.x`; shipped
   expanders become `src/builtins.x`; user meta groups stage through the
   native-module path with a per-unit reset for `meta static`; the
   generated `.xlisp` files and `tools/gen-lisp-init.py` go. Migration
   detail is `design-synthesis.md` sections 3 and 7.
3. The evaluator: trampoline, per-call-site `defmacro` memo, AUTO and
   `lib/lisp-machine.x` removed, `lib/machine.x` Match-only, eager parent
   session, lifecycle flags and `<lisp-late>` gone.
4. One lowering walk (`src/lower.x` from `transform.x`, `lambda.x`,
   `cleanup.x`), cache ids recorded as emitted, no private emitter kinds.
5. Front end: one classifier with skip-body mode, frames for transactions,
   parse-then-bind with one installer, rule-list conversion, ranked
   protocol clauses, one typedef walker, the initializer cursor.
6. Runtime: Array and Map as family instantiations (E5), the one-Pool error
   record then the frame chain (E6), one value-transfer walk, one
   recursive-mutex primitive, `Block`/`Buffer` growth as one family.
7. Match: only if a prototype of the journaled engine translates `src/`
   and `lib/` within 1.12x; otherwise the compiled engine stays and the
   plan table (E9) is the remaining candidate.

A drop is justified only when its sole consumer is the deleted engine, or
an ordinary mechanism reproduces its observable behavior with the lines
saved stated; never when it changes an existing program's generated C, a
runtime module's documented contract, or a consumer's command-line surface
without Gary's decision. `commands/` and `packages/` are consumers whose
compiler surface (`ledger.md`, map section 2.12) must survive unchanged.

## Decisions for Gary

- REPL: under native meta execution a submission that defines meta code is
  staged as a module, 100-300 ms against about 1 ms today, and `:stats`
  loses its AUTO fields. Past the rope for that one consumer; the CLI
  surface survives.
- Autodiff: `lib/autodiff.xmacro` and `lib/autodiff.x` (1,566 lines) have
  no consumer in `src/`, `lib/`, or `commands/` except one include; moving
  them to `packages/` takes their fixtures out of `make check`.
- The language change: withdraw `x2c_comptime_lower` and the compile-time
  subset's rejection table (the engine deletion depends on it); retire the
  legacy macro body forms; optionally the quoted `%[...]`/`%{...}` forms
  (80 lines, one fixture check open).
- Whether to fund a prototype of the journaled Match engine, the only
  remaining trade worth more than 1,000 lines and the only one at the edge
  of the rope.
- Small drops listed in `ledger.md` section 5 that touch documented
  surface: `Var.parse`, alias methods, `Pool.child_capacity`, public
  helpers made private.

## Found in passing

- `lib/match.x`: a call-site plan's normalized pattern is retained past
  the pool that allocated it (task card queued).
- `lib/lisp.x`: the evaluator has no tail calls; the wordcode tier is
  load-bearing for depth today, not only for speed.
- The sample shares cited in `plans/archive/comptime-x2c-generalization.md`
  as "now" belong to an unmerged branch; current `dev` matches its
  "before" column (compile-time Lisp 3.8-4.1%, macro expansion 11-15%,
  Match 10.4-12.5%).
- Regions of source no reader finished: `src/comptime.x` past ~1300,
  `lib/match.x` 2260-2677, `lib/autodiff.xmacro` past ~900,
  `lib/error-private.xmacro`, `lib/string.x` beyond a skim.
