# x2c lowers to Lisp

> Status: active
>
> Design decided, nothing implemented. Work happens on the isolated branch
> `x2c-lowers-to-lisp` and does not reach `main` without Gary's explicit
> green light. Measurements below were taken on 2026-09-17 against
> `82bd746b` and decide the design.

## The result

One language, three faces. x2c source is the only thing an author writes,
whether it becomes a runtime function, a compile-time function a macro
calls, or the body of a macro template. Compile-time Lisp stops being an
authoring surface and becomes the intermediate language: x2c lowers to
Lisp, and the existing evaluator and word-code machine execute it.

A compile-time function is an ordinary x2c function marked so the compiler
lowers it and keeps it callable during translation. A macro invokes it the
way it invokes a Lisp function today. The same function may also be
compiled to C when a program calls it at runtime.

Nothing about the Lisp runtime is removed. `Lisp`, the evaluator, the
machine, `etc/init.xlisp`, and the `bind` surface stay exactly as they are,
and hand-written Lisp remains legal. What shrinks is the amount of Lisp
anyone has to write to support macros.

## Why this is worth doing

Two arguments, one from cost and one from fit.

The cost is visible in the tree: about 1,000 lines of Lisp under `etc/`
plus roughly 700 more inside `lib/autodiff.xmacro`, most of it
re-deriving in Lisp what x2c already does. The
[compile-time value surface](../etc/lisp-values.xlisp) shipped on
2026-09-17 is the clearest evidence: 69 names whose only purpose is to let
Lisp stop reimplementing the x2c library.

The fit argument is stronger. `autodiff.xmacro` is AST rewriting written in
the one language worse at it than the host. x2c's `match` has typed
captures, `!set`, `!or`, and literal output templates the compiler checks;
Lisp's `match-case` has none of that. Moving that code to x2c makes it
shorter and reviewable.

## The pipeline

```text
x2c source
  -> parse / bind / type            (existing, unchanged)
  -> typed AST                      (existing, unchanged)
  -> LOWER TO LISP                  (new: one pass)
  -> Lisp evaluator + word machine  (existing, unchanged)
```

Only the middle step is new. The `.context/spike/c-from-ast.xlisp`
prototype already performs it for a useful subset, which is how the
measurements below were obtained.

## Settled decisions

### Lower to direct forms, never to thunks

This is the decision the measurements make, and it is a 49x difference.

The spike's SDK wraps each statement in `(lambda () ...)` and passes loop
clauses as thunks. A production lowering must emit direct forms instead:
locals become lambda parameters, a loop becomes a self tail call, and a
statement sequence becomes nested `cond`.

Same function, `int spin(int n)` summing `i & 7` over `n` iterations, in
one `Lisp.kernel()` session with `etc/init.xlisp` loaded:

| lowering | 20,000 iterations | Lisp calls | machine entries |
|---|---|---|---|
| thunk SDK | 1,310 ms | 380,186 | 280,135 |
| direct forms | 26.8 ms | 1 | 1 |

The direct form runs 100,000 iterations in 148.8 ms, about 672,000
iterations per second, and the whole loop is **one** machine entry: the
word machine executes it without returning to the evaluator. The thunk
version reaches the machine 74% of the time and is still 49x slower,
because it makes about 19 Lisp calls per C iteration.

So `C.while` and `C.for` as SDK procedures are the wrong shape. The
lowering emits the control flow directly; any macro spelling is a macro
that expands to direct forms.

### Nothing may stand between a loop and its recursive call

Measured 2026-09-17 while starting M0, and it constrains the lowering more
than anything else. The evaluator reuses a frame only for a **direct self
tail call**. A tail call to any other lambda retains the caller's
environment, so a loop whose body reaches its recursive call through one
more call accumulates environment per iteration:

| loop body shape | 500 | 2,000 | 20,000 |
|---|---|---|---|
| direct self tail call | - | - | 25 ms |
| through an anonymous lambda (`let*`) | 109 ms | 1,682 ms | segfault |
| through a named global continuation | - | 1,565 ms | segfault |

The cost is superlinear and ends in a stack overflow, so neither shape is
usable. `let*` sequencing inside a loop body is therefore out, and so is
the obvious continuation-passing lowering.

The body must instead reduce to one expression per live local, computed
from the values at the top of the iteration, so the iteration ends in
`(loop e1 e2 ...)` directly. That is a substitution pass over the block:

- straight-line assignments substitute symbolically, so
  `t = a % b; a = b; b = t;` becomes `(loop b (_binary a '<"%"> b))`;
- an `if` puts a complete tail call in each branch, which `cond` expresses
  and which keeps every path direct;
- `continue` is the tail call with the current expressions; `break` and
  normal exit are a single tail call to the continuation, which happens
  once per loop rather than once per iteration and so costs nothing.

Two cases cannot be substituted and are **declined with a diagnostic**
rather than lowered wrongly: an impure expression used more than once,
and more than one live local whose expression has effects, because the
argument order would reorder them. Both are rare and the refusal names the
function.

**Locals an inner loop assigns, and locals whose address is taken, stay in
the frame `Map` instead of becoming parameters.** A nested loop is an
ordinary non-tail call that returns, and a Lisp function returns one value,
so it cannot hand several updated locals back to its caller. Routing those
through memory avoids the problem, and the spike already draws exactly this
distinction for address-taken locals. Map-backed locals cost a lookup;
parameter locals cost nothing.

### Measured: the machine's parameter ceiling

Locals-as-parameters has a ceiling. `LISP_AUTO_PARAM_MAX` in `lib/lisp.x`
is 8, and a lowered loop carrying more parameters than that falls off the
machine onto the evaluator. Measured with 3,000 iterations and a varying
number of carried locals:

| carried locals | total parameters | cap 8 | cap 32 |
|---|---|---|---|
| 5 | 8 | 9.9 ms | 9.9 ms |
| 6 | 9 | 1,102 ms | 10.6 ms |
| 10 | 13 | 1,322 ms | 15.3 ms |
| 20 | 23 | 2,770 ms | 32.8 ms |
| 30 | 33 | 5,360 ms | 2,950 ms |

The cliff is exactly the constant, and raising it moves the cliff. It is
not an architectural limit: `MACHINE_VALUE_MAX` is 256, so 32 parameters
leaves ample slot budget. Raise it to 32 and lower functions whose live
set exceeds that through a single frame `Array` instead, which keeps them
eligible at one parameter and slower element access.

### Keep the existing native boundary

A lowered function calls natives through the same table `bind` already
uses, and `$lisp.bind` already refuses an ineligible signature at compile
time with `native binding parameter type has no Var representation`. That
diagnostic is the specification of what a compile-time function may call:
`Var`, `Symbol`, `String`, `List`, `Array`, `Map`, `File`, `Iter`, `Func`
and the numerics; not `char *`, pointer out-parameters, or variadics.

No new mechanism is needed. A call to a function with no binding is a
translation-time diagnostic naming the function, which the spike already
produces.

### The reduced subset, decided by the spike rather than by taste

The spike translated and executed 22 functions whose compile-time results
match native execution bit for bit. What came out mechanically is in;
what the spike hit a wall on is what needs a decision.

**In** (proven by the spike): `if`, `while`, `for`, `do`/`while`,
`switch` including fall-through, `break`, `continue`, `return`, blocks and
nested scopes, the full C operator set with x2c promotion and wrapping,
recursion and mutual recursion, `int` and `double`, arrays with
initializers, pointers to locals, pointer arithmetic, casts between
arithmetic types, and the `List`/`String`/`Map`/`Array`/`Var`/`Symbol`
operations.

**Out for now**, each because it needs a decision rather than more typing:
`goto` and labels; `struct` declarations and field access; `defer`;
`foreach`; `match`; `try`/`catch`. `struct` and `match` are the two that
matter for porting `autodiff.xmacro` and are the first extensions.

### Isolation

All work stays on `x2c-lowers-to-lisp`. No push to `main`, no PR against
`main`, until Gary says so.

## Implementation

### M0 - prove the lowering on the machine  (DONE 2026-09-17)

Implemented in `.context/spike/lower-direct.xlisp`. The lowering substitutes
straight-line assignments symbolically, puts a complete tail call in each
`cond` branch, emits one global function per loop, and inlines the rest of
the block at the loop's exit. It screens the function first and hands
anything it cannot carry to the SDK lowering, so all 22 spike functions
still match native execution.

Measured end to end, the whole compiler run including startup and
translation, against a 0.46 s baseline with no compile-time call:

| workload | SDK lowering | direct lowering |
|---|---|---|
| `spin(100000)` | 12.07 s | 0.77 s |
| `spin(1000000)` | - | 3.85 s |

That is about 295,000 loop iterations per second against 6,800, a 43x
improvement, and it stays linear to a million iterations. It is 2.3x short
of the 672,000 the hand-written ideal reaches, because every operator still
goes through `_binary` with a Symbol rather than Lisp's own `+` and `<`;
closing that gap is an M1 question, because `<` returns a Lisp truth value
rather than a C `int` and the two uses have to be told apart.

Three constraints the implementation ran into, each recorded because it
shapes M1:

- **Generated names must be at most seven characters.** A compact `Symbol`
  packs seven characters of this alphabet and silently truncates beyond
  that, so `lower.loop1` becomes `lower.l` and two loops would collide.
  Names are therefore positional: loops are `lwN`, parameters are `pN`.
- **Substitution duplicates work.** A local read several times has its
  expression copied to each read, which can grow the body past what the
  machine will prepare; the result then runs on the evaluator. A size
  guard declines a substituted value over 512 nodes. A wide live set is
  still not machine-prepared, and the binding limit there is
  `MACHINE_CODE_MAX`, not the parameter count.
- **`binder?` in `etc/init.xlisp` misses long binders.** A binder of ten
  or more characters reads as an `lsym` rather than a `Symbol`, and
  `symbol?` is false for it, so `match-case` does not bind it while
  `match` does. Changing `binder?` to accept both broke the spike's own
  translation for reasons not yet understood, so the lowering avoids long
  binder names and the defect is left for its own investigation.

### Superseded: raise `LISP_AUTO_PARAM_MAX` from 8 to 32

Kept for the measurement, not adopted. The synthetic carried-locals
benchmark below is real, but on a function with a wide live set the raise
bought nothing end to end, because substitution had already grown the body
past the machine's code budget. Raising it also invalidates the premise of
`lisp_auto_declined_form_releases_programs`, which uses a nine-argument
call as its example of a form that declines. Revisit in M1 together with
the code-size limit, since neither is worth changing alone.

### Original M0 statement

Implement the substitution lowering above for the loop shapes it covers,
keeping the spike's existing path for everything it declines, so the 22
functions keep passing while the fast path is proved. Raise
`LISP_AUTO_PARAM_MAX` to 32 with the carried-locals measurement as its
evidence. Proof: the spike's 22 functions still match native, and
`spin(100000)` runs in under 200 ms as one machine entry.

The two-path arrangement is scaffolding for this milestone only. M1 either
extends the substitution lowering to cover everything or records why a
second path is permanent.

### M1 - the compile-time function

Decide and implement the source spelling, lower a marked function at
definition, and make it callable from `$(...)`. Proof: a compiler fixture
where a macro calls a compile-time function written in x2c and the result
reaches the program as a literal.

### M2 - `struct` and `match`

Extend the subset with the two constructs `autodiff.xmacro` needs. Proof:
fixtures for each, and the existing `match` fixtures unchanged.

### M3 - port `autodiff.xmacro`

Rewrite its roughly 700 lines of Lisp as x2c compile-time functions. This
is the measurement that decides whether the whole direction pays: report
the line count before and after and whether the derivative tests still
pass unchanged. Proof: `unittest/test-autodiff.x` and the autodiff book
chapter examples pass with no change to their expected output.

### M4 - review and report

Review the completed authored diff for trusted facts, deletion and reuse,
and unnecessary machinery, and fix what it finds. Then report the total
Lisp removed and recommend whether to continue to the remaining Lisp in
`etc/`.

Stop and report at the end of M3 regardless of outcome. If autodiff does
not get meaningfully shorter and clearer, the direction is wrong and the
branch should be archived rather than extended.

## Compatibility

Nothing shipped changes behavior. The lowering is additive, the native
boundary is the existing one, and hand-written compile-time Lisp keeps
working. Raising `LISP_AUTO_PARAM_MAX` makes more Lisp eligible for the
machine and changes no result; it is covered by the existing
`test-lisp-auto.x` suite.

## Validation

Ordinary focused checks during the work: `make x2c` plus the fixtures for
the construct being added. `make verify` before each milestone's report,
and `tools/gate-state.py ensure agent-pr-check` only when Gary green-lights
delivery.

## Plan review

**Facts already established by existing producers.** The typed AST from a
`Unit` capture carries unique binding ids and a resolved type on every
expression, and resolves a method call to its runtime function, so the
lowering does not re-derive scope, types, or method resolution. `Var`
supplies C integer promotion, width-correct wrapping and floating
promotion, so the lowering emits operators and adds no arithmetic of its
own. `$lisp.bind` already decides which natives are reachable. No proposed
consumer rechecks any of these.

**What this deletes or reuses.** It reuses the parser, binder, typer,
Lisp evaluator, word machine, native table, and `etc/lisp-values.xlisp`
unchanged; the only new lasting mechanism is the lowering pass itself. It
is expected to delete roughly 700 lines of Lisp in `autodiff.xmacro` and,
if that succeeds, most of the Lisp under `etc/`. The one constant change
replaces no code but removes a cliff that would otherwise force a second
lowering strategy for functions with many locals.

**Why the source is idiomatic x2c.** The lowering is one `match-case` per
AST production producing a literal output template, which is the shape
`agents/replacing-manual-ast-walks-with-match.md` prescribes; the spike is
written that way already. Nothing here imports a framework: the execution
substrate, the value model, and the native boundary are all x2c's own.

**Validators, diagnostics, and negative fixtures.** One: a call to a
function with no compile-time binding is refused at translation with the
function's name. It protects against silently producing a wrong
compile-time result for a function the session cannot execute, which is
not detectable later. No other validator, and no negative fixture beyond
that one diagnostic.
