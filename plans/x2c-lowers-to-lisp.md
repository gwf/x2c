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

### Raise `LISP_AUTO_PARAM_MAX` from 8 to 32

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

### M0 - prove the lowering on the machine

Port `.context/spike/c-from-ast.xlisp` to a direct-form lowering and
confirm one representative function runs as a single machine entry at the
rate measured above. Raise `LISP_AUTO_PARAM_MAX` to 32 with the carried
-locals measurement as its evidence. Proof: the spike's 22 functions still
match native, and `spin(100000)` runs in under 200 ms.

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
