# x2c lowers to Lisp

> Status: active
>
> Design decided and built. `src/comptime.x` is the compiled pass and
> `etc/comptime.xlisp` its runtime; the whole of `lib/autodiff.xmacro`'s
> forward and reverse modes is ported and exact. Work happens on the isolated
> branch `x2c-lowers-to-lisp` and does not reach `main` without Gary's
> explicit green light. Measurements from 2026-09-17 against `82bd746b`
> decide the design; those from 2026-09-18 record what the pass now does.
> Making the pass general enough to replace the remaining macro Lisp is
> scoped separately in `plans/comptime-x2c-generalization.md`.
>
> This file is the design record and its narrative cites spike files under
> `.context/spike/`, which were per-worktree working files and are gone. What
> survives is tracked: the pass in `src/comptime.x` (named `src/lower.x` here),
> its runtime in `etc/comptime.xlisp` (named `etc/lisp-lower.xlisp` here), the
> fixtures under `unittest/compiler-fixtures/comptime-*`, and the value-type
> reference in `plans/reference/`. Read a `.context/spike/` citation as
> evidence that was taken, not as a file to open.

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

Only the middle step is new. The `plans/reference/lisp-lowering-values.xlisp`
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

**Superseded by the evaluator.** A call in tail position now reuses the
frame whatever prepared Lambda it names, and `let` lowers into slots of the
frame it stands in, so neither shape below accumulates environment. The
lowering the section describes is still what `src/comptime.x` emits; the
measurements are kept as the record of why it was chosen.

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
translation, against a 0.49 s baseline with no compile-time call. Re-taken
on `48b7d458` after the match and lisp changes landed, because those are on
the path the lowering exercises:

| workload | SDK lowering | direct lowering |
|---|---|---|
| `spin(100000)` | 14.03 s | 0.82 s |
| `spin(1000000)` | - | 3.79 s |

That is about 303,000 loop iterations per second against 7,400, a 41x
improvement, and it stays linear to a million iterations.

The direct path is unchanged from the earlier tree while the SDK path slowed
from 12.07 s to 14.03 s for the same work. I guessed the added `car`/`cdr`
argument check; that guess was wrong. A controlled probe over roughly
400,000 `car` and 400,000 `cdr` calls, run interleaved against both trees,
found current main slightly faster, so the check costs nothing measurable.
Both of my numbers time a whole compiler run, and the parser, emitter and
generator all changed between the trees, so the difference most likely sits
in translation rather than in the compile-time evaluation. Timing only the
evaluation on one tree would settle it; it does not affect the 41x result,
which compares two paths on the same tree. It is 2.3x short
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

### M1 - the compile-time function  (PROVEN IN THE SPIKE 2026-09-17)

`.context/spike/comptime.x` runs end to end: `$comptime()` marks a
function, `$at(...)` calls it during translation, and the generated C holds
`55, 5050, 500500` and `1627576247` as literals where the source called
`triangle` and `mix`. The same functions still compile and run normally, and
their run-time and compile-time results agree, including a `double`.

The spelling is a `Unit` decorator, chosen because it needs no parser
change and is reversible. A keyword is the eventual spelling and is not
decided here.

What remains before this could ship, and deliberately not done yet: the
lowering and the SDK still live in `.context/spike/`, so there is no
compiler fixture. Moving them into `etc/` is only worth doing once M3 says
the direction pays, so the fixture waits for that.

### M2 - `match` and templates

Reading `autodiff.xmacro` corrected the target: what it needs is `match`
over ASTs and `%(...)` templates, not `struct`. Both are how it does its
work, and `struct` barely appears.

**Blocker found and cleared.** Neither is visible in the syntax a macro
receives. Literal folding hoists a constant `List` into the compiler cache
and leaves `(cache ID)` behind, so `case %(add ?a ?b)` arrives as
`(expr ("List") (expr ("List") (cache 5)))` and a template's constant head
is a cache id too. The cache is a DAG of ids over `(cons ...)`, `(var ...)`
and `(string ...)` leaves.

`_x2c.cache.value` now returns one cached constructor form, and
`.context/spike/cache-values.xlisp` walks the DAG to rebuild the value.
`case %(add ?a ?b)` reads back as the List `(add ?a ?b)`, which is exactly
what Lisp's own matcher takes, so lowering a `match` statement hands the
pattern to `List.match` rather than reimplementing it.

**Both are now lowered.** `.context/spike/match-lower.x` runs an x2c
function that matches `%(add ?a ?b)` and returns `%(sum $a $b)` during
translation, and the arms, the binders and the fall-through all give the
right answer. A `case` becomes `(match subject 'pattern)` against Lisp's
own matcher, and a binder reads its value with `bound`.

A binder repeats the match rather than naming its result. Matching is pure,
so that is correct, and it keeps an arm free of a binding form, which
matters because a lambda is free once per entry and fatal once per
iteration on a loop's path. The cost is one extra match per binder; for an
arm with two or three binders that is cheaper than it looks, and naming the
result would cost more on a loop path than it saves.

### Open question for Gary: how a macro should read a folded literal

**Answered.** The accessor is bound as `x2c.cache.value`, without the
`_x2c.` prefix, so it is public compile-time surface. The rest of the
section records the alternatives that were weighed.

Raised by the review session and worth deciding before M3 builds on it.

`_x2c.cache.value` takes an integer and returns `compiler.id_keys[id]`.
The objection is fair: an id is a handle into a table whose numbering is an
implementation detail, nothing ties the id to the form the macro was given,
and `AGENTS.md` says ordinary operations accept forms by structure and
position. The `_x2c.` prefix reads private, but a macro depending on it
makes it public compile-time surface.

The alternatives offered were to emit `(cache id key)` so the key rides
along, which costs a larger AST for every folded literal and partly defeats
what folding is for, or to defer folding for forms that reach a macro,
which is cleaner but needs to know at literal-parse time which forms those
are.

One correction to the framing: this is not optional for the lowering. A
`case` pattern reaches a macro only as a cache id, so lowering a `match`
statement cannot work without reading it back. The question is the shape of
the accessor, not whether one is needed.

**Rejected after measuring its runtime cost.** It looked free and is not.
`Compiler.runtime_literals` already disables folding, and
`Compiler.parse_catch_pattern_literal` already sets it for catch filter
patterns. A match arm sets `in_pattern` but not `runtime_literals`. Adding
`$let(c.runtime_literals, 1)` beside the existing `$let(c.in_pattern, 1)`
in `_match_case` makes a `case` pattern fully structural: it reaches a
macro as the `cons` chain the source wrote.

What that costs, measured on `src/transform.x`:

| | folded | unfolded |
|---|---|---|
| translate | 0.44 s | 0.43 s |
| generated C | 156,758 B | 150,749 B |

Translation time is unchanged and the output is 4% smaller, which is what
misled me: I concluded the cache slots were dead weight. They are not. The
generated C stops referencing a cached constant and instead rebuilds the
pattern on every match execution:

```c
// before
x2c_match_site_try_capture(&site, expr, List_var(_3), &capture)
// after
x2c_match_site_try_capture(&site, expr,
  List_var(cons(List_var(cons(Symbol_var(982), NULL)), NULL)), &capture)
```

Over 8,000,000 matches that costs about 5%: 0.090 s against 0.085 s. Small,
but it is a permanent tax on every `match` in every program, and the
compiler itself is full of them. Since the accessor already reads patterns,
this buys convenience and nothing else.

It also solves only half the problem: a template such as `%(sum $a $b)` is
not in a pattern position and cannot be marked at parse time, so an
accessor is needed regardless.

**Both remaining options built and measured, on `src/transform.x`.**

| | 1: accessor keyed on the node | 2: `(cache id key)` |
|---|---|---|
| reads patterns | yes | yes |
| reads templates | yes | yes |
| translate | 0.44 s | 0.48 s |
| generated C | 156,758 B | 156,737 B |
| peak RSS | 46.8 MB | 47.2 MB |
| fixtures | 716 pass, nothing to regenerate | 54 artifacts to regenerate, no behavior failure |
| the change | 1 file, 14 lines | 7 files |
| new API | `x2c.cache.value` | none |

Option 2 costs about 10% of translation time on every unit, permanently,
and its output is the same size, so the AST it grows is pure overhead. It
also changes a node shape that eight places match on: the first attempt
missed `src/transform.x:85`, which broke `printf-var-lowering` until it was
found, and every future matcher written as `%(cache ?id)` instead of
`%(cache ?id *)` would break the same way.

Option 1 measures identical to doing nothing, because it changes no syntax.
Its concession is one documented operation whose argument is a node the
macro was handed rather than an index it invented.

**Adopted: option 1**, together with the free pattern fix. Purity is worth
paying for, but not 10% of every translation plus a shape that every future
consumer has to remember.

### M3 groundwork - lambdas  (DONE 2026-09-17)

Surveying `autodiff.xmacro` first changed what M3 needs. Its 754 lines of
Lisp use 65 lambdas, 52 templates, 24 `match-case` and 19 mutable globals.
Templates and `match` were M2. Lambdas were not supported at all, and at 65
uses they are the largest single dependency.

Lambdas now lower. An x2c lambda becomes a Lisp lambda, and because the
environment substitutes a local's expression rather than naming it, a
captured value is inlined, which is exactly the by-value snapshot x2c gives
a captured scalar. A lambda inside a call argument never reaches the
statement lowering, so expression translation marks it `(C.lambda ids
captures body)` and substitution turns it into the real lambda where the
environment is in scope.

`.context/spike/lambda-lower.x` runs `xs.map(%!(Var item) => item.integer()
* by)` at translation time with `by` captured, and all seven spike programs
still agree with native execution.

Two smaller things this needed. Slot names are now unique within a function
rather than positional, because a lambda's parameters sit inside the
enclosing environment and must not shadow it. And eligibility no longer
rejects every call: it rejects a callee with no compile-time binding, which
is the case expression translation would raise on.

### M3 groundwork - file-scope state  (DONE 2026-09-17)

A global is an id the function never declares. Its value cannot be
substituted, because a write between two reads changes it, so a read stays
a read and a write is an effect. The effect rides a `cond` test that always
fails, which keeps the rest of the block in tail position and introduces no
binding form, so a global write is legal on a loop's iteration path.
Globals live in a `Map` keyed by binding id, which avoids inventing names
under the seven-character limit. A unit-level initializer is not part of
the function, so an unwritten global reads as zero.

`.context/spike/globals-lower.x` calls `bump(5)`, `bump(3)`, `bump(2)` at
translation time and gets 5, 8, 10.

One defect this exposed, worth recording because it was silent. The scan
that decides which ids are local stopped at the first `bind` node it
matched, and a function's own binding carries its parameters underneath, so
every parameter looked like a global. `gcd` then wrote its parameters to
the global store and looped forever instead of updating them. The walk now
collects an id and still descends.

All eight spike programs agree with native execution.

### M3 - port `autodiff.xmacro`  (SLICE DONE 2026-09-17)

`.context/spike/autodiff-slice.x` ports the forward-mode arithmetic core:
`ad_zero`, `ad_one`, the four simplifying constructors, the two predicates,
and `ad_tangent`. All twelve lower directly, none fall back, and every
result matches what the Lisp original computes, including the
simplifications that make `0 + x` read back as `x` and `1 * x` as `x`.

**The line count is parity: 54 lines of x2c against 55 of Lisp**, plus one
`$comptime()` marker per function. That was this milestone's stated
measure, and on it the port does not pay.

**The stated measure was the wrong one.** Size is not what changes. What
changes is that the x2c version is also a C function.
`.context/spike/dual-use.x` calls the same `ad_mul` both ways and gets the
same answer:

```text
compile time  ad_mul(0, x) = (expr (double) (literal (double) "0.0"))
run time      ad_mul(0, x) = (expr (double) (literal (double) "0.0"))
```

One source, compiled to C and run, and lowered to Lisp and run during
translation. The Lisp version can only ever do the second. That is a
capability the Lisp cannot have, not a matter of taste, and it decides the
milestone in a way line count cannot.

The port also buys types and compiler-checked templates: a `case` pattern
and a `%()` template are checked where Lisp's are data.

**Five defects in the lowering surfaced only under real code**, which is
worth recording because it says something about how much is left:

- a Symbol literal was translated as a number, so every operator in a
  template came out as `0`;
- a cached leaf holding a cached `List` was returned unexpanded;
- a cached `String` holds its value, not its source spelling, and was being
  unquoted a second time;
- an empty `()` template element was returned as its node;
- a zero-argument call carries one void placeholder argument, which
  expression translation rejected.

Each was a few lines to fix. None were visible in the constructed examples
of M0 through M2. The port needed one further lowering feature as well: a
value that cannot be substituted is now bound with a real lambda when it is
off a loop's iteration path, and declined on it.

**Two further slices ported.** `.context/spike/autodiff-slice2.x` has the
syntax-rewriting helpers, including a recursive walk that strips binding
records from a copied subtree. `.context/spike/autodiff-slice3.x` has the
forward-mode statement walker: `ad_fwd_item`, `ad_fwd_items` and
`ad_fwd_body`, mutually recursive, producing a correct forward-mode body
from a real one. Twenty-six functions are ported in all, every one lowers
directly, and every one computes what its Lisp original computes.

Nine more lowering defects surfaced across these two slices, none of them
visible in constructed examples:

- a Symbol literal was translated as a number, so every operator in a
  template came out as `0`;
- a cached leaf holding a cached `List` was returned unexpanded;
- a cached `String` holds its value, not its spelling, and was unquoted
  twice;
- an empty `()` template element was returned as its node;
- a zero-argument call carries one void placeholder argument;
- a `String` literal constructs through `String_new` with a bare string
  callee rather than a binding;
- a folded `String` wraps that constructor call in the cache;
- a spliced element builds an `append` node, which was unhandled;
- the truth test was numeric only, so a nil `List` read as true. It now
  inlines the numeric comparison when the static type is numeric and asks
  for x2c truth otherwise.

Execution speed is unchanged: 100,000 loop iterations still cost about
0.36 s. The whole-run number grew only because the spike itself is bigger
to translate.

Two x2c facts the port depended on, recorded because they are easy to get
wrong: a `match` arm takes exactly one statement, so several need braces,
and `List` has no `concat` — splicing two lists into `%(@a @b)` is the
idiom, which builds the `append` node above.

**Forward mode is fully ported and works end to end.**
`.context/spike/autodiff-fwd.x` holds thirty compile-time x2c functions
that generate a derivative function, which then compiles to C and runs:
`square_dot(3) = 7.0` and `poly_dot(2) = 17.0`, both correct.

### Size and speed against the original

Same work, same two derivatives, measured against `lib/autodiff.xmacro`.

**Size: the port is larger.** 236 lines of x2c against 191 lines of Lisp
for the equivalent functions, plus one `$comptime()` marker each. About 24%
more.

**Speed: the port is far slower to translate.**

| | translate |
|---|---|
| original, `$ad.forward()` | 241 ms |
| port, `$c.derive()` | 79 s |

That is 330x. Splitting it says where it goes:

| | translate |
|---|---|
| parse the thirty functions, lower nothing | 154 ms |
| lower them, derive nothing | 76.7 s |
| lower them and derive | 79.0 s |

So 97% of the cost is the lowering pass itself, not the generated code and
not the derivation.

**Optimised from 79 s to 2.9 s.** The causes, in the order they mattered:

| change | 30 functions + 2 derivations |
|---|---|
| as first written | 79 s |
| head dispatch instead of `match-case` in the hot paths | 22 s |
| call table as a `Map` instead of an association list | 7.7 s |
| one scan instead of six walks of the same tree | 4.0 s |
| `foldl` instead of `map` for a walk done for effect | 2.9 s |

The `Map` change is the one worth repeating: every call in a lowered
program went through `C.call`, which scanned an association list of about
seventy entries. Replacing it with a `Map` made *deriving* essentially
free. Before it, five derivations cost 7.4 s more than zero derivations;
after it, five cost 0.1 s more. The handwritten Lisp calls its helpers
directly, so the lowering had been paying a search the original never pays.

What remains is a fixed cost, and measuring the slope rather than one
point changes the conclusion. Deriving n functions in one unit:

| derivations | original | port |
|---|---|---|
| 0 | 93 ms | 2.89 s |
| 5 | 646 ms | 2.95 s |
| 20 | 2.07 s | 3.29 s |
| 50 | 5.00 s | 3.90 s |

**Per derivation the port is about 20 ms and the original about 98 ms**, so
the ported algorithm runs roughly five times faster than the Lisp it
replaces. The port carries a 2.89 s fixed cost for lowering its thirty
functions once, against 93 ms to load the `.xmacro`, and the two cross at
about 36 derivations in a unit.

### Prelowering would not help: it already happens

The lowering's own Lisp is already compiled. Reading the macro session's
statistics after lowering thirty functions: 72,044 evaluator invocations,
50,308 of them machine entries, 8,518 analyses, 8,511 programs published,
7 ineligible. So the machine compiles essentially all of it, lazily, after
each lambda's second call.

Publishing is not the cost either. Replacing the closures the walks passed
to `map` with named recursion halved the published programs, 8,511 to
4,214, and left the time unchanged.

What costs is calls. Lowering thirty functions of about 7,500 AST nodes
takes roughly 123,000 Lisp calls, about sixteen per node, and per-call
overhead is what fills the 2.9 s. Compiling the same thirty functions as
ordinary x2c, parse and type with no lowering, costs 162 ms, so the pass is
about seventeen times its own subject.

Closing that means fewer calls per node, or writing the pass in x2c and
compiling it, which is where this plan was always going. Compiling the Lisp
ahead of time is not the lever, because the Lisp is already compiled.

### The pass in x2c  (FIRST WORKING VERSION 2026-09-17)

`src/lower.x`, 700 lines, with `etc/lisp-lower.xlisp` holding the 95-line
runtime the lowered code calls. `x2c.comptime.install` lowers a function and
evaluates the result in the macro session; `x2c.comptime.lower` returns the
forms for inspection. 716 fixtures and 915 unit tests pass.

Thirty functions, each with a `while`, a `for`, an `if` and a `return`:

| | translate |
|---|---|
| parse and type only, no lowering | 125 ms |
| compiled pass | 147 ms |
| Lisp prototype | 2.57 s |

So the pass costs 22 ms for thirty functions, 18% of what parsing them
costs, and is 111 times faster than the prototype. That is the result the
scope predicted.

Three things the x2c version gets for free. `Atom.intern` gives an `lsym`
for a long spelling, so generated names are readable and cannot collide by
truncation. `String.try_long` and `String.try_double` replace forty lines of
digit arithmetic. And the dispatches are `match` statements again, compiled
to a decision tree, rather than the hand-rolled `cond` chains the prototype
needed to avoid `match-case` re-expansion.

A call is now a direct Lisp call: the callee's name is a session global, so
`C.call` and its lookup are gone entirely.

Still to port: `match` statements, which the autodiff port needs, and the
value types beyond `int` and `double`. The prototype keeps working
meanwhile.

### Scope of writing the pass in x2c

Measured against the prototype as it stands, 1,057 lines of Lisp across
five files.

| | lines | becomes |
|---|---|---|
| `lower-direct.xlisp` | 385 | x2c, mostly `match` statements |
| `c-from-ast.xlisp`, expression half | 277 | x2c, mostly `match` statements |
| `cache-values.xlisp` | 40 | x2c, and shrinks: the pass holds `id_keys` |
| `c-from-ast.xlisp`, SDK fallback | 102 | deleted |
| `c-sdk.xlisp`, C-machine half | 77 | deleted |
| `c-sdk.xlisp`, remainder | 29 | stays Lisp: the lowered code calls it |
| `runtime-bridge.xlisp` | 88 | stays Lisp, or x2c data |

So about 700 lines port, about 180 are deleted, and about 120 stay Lisp as
the runtime the lowered code calls. The SDK fallback goes because it exists
only to catch what the direct lowering declines, and a compiled pass should
cover those cases instead.

The ported 700 should not grow. x2c measured 24% larger than equivalent
Lisp on the autodiff slice, but that comparison was against Lisp using
`match-case`; the prototype has since had six dispatches rewritten as
hand-rolled `cond` chains on the head to avoid its re-expansion cost. In
x2c those go back to `match` statements over AST productions with `%()`
output templates, which is both shorter than the `cond` chains and compiled
to a decision tree.

Work beyond transcription, which is where the estimate is softest:

- a new `src/` module and its place in the pipeline;
- invoking it from the macro path when a function is marked, instead of
  from a decorator that calls Lisp;
- the native name table, currently 88 lines of Lisp `C.native` rows;
- extending the direct lowering to cover what the fallback covers today,
  since the fallback is being deleted.

Nothing here needs a language feature the checked-in bootstrap lacks, so
there is no staged-capability problem. The seven-character limit on a
generated `Symbol` still applies.

Expected result: compiling those same thirty functions as ordinary x2c,
parse and type, costs 162 ms, and the pass does comparable work, so
100-200 ms against the prototype's 2.9 s.

### What the word machine contributes

The pipeline is x2c source, to Lisp lambdas, to the word machine, and the
machine is doing real work. Disabling it with `Lisp.auto_disable` on the
compiler's own macro session:

| | machine on | machine off |
|---|---|---|
| lower 30 functions | 2.90 s | 9.83 s |
| 50 derivations on top | 3.95 s | 11.21 s |

So the machine is worth 3.4x on the lowering pass, and per derivation the
difference is 21 ms against 28 ms. Running a derivation is cheap mostly
because the call table became a `Map`, not because of the machine; the
machine is what makes the one-time lowering affordable.

The reason the port is faster is the same `match-case` cost measured above,
from the other side: `autodiff.xmacro` uses `match-case` throughout, so it
re-expands a macro on every call, while the lowering emits a direct
`(match subject 'pattern)` against the native matcher. Lowering from x2c
produced Lisp that avoids a trap the handwritten Lisp falls into.

**The first cause was `match-case`, and it is not specific to this
prototype.**
`match-case` is a `defmacro`, and `_apply_lambda` in `lib/lisp.x` expands a
macro and then evaluates the expansion on *every call*. The nested
`cond`/`let` structure a `match-case` with sixteen clauses builds is
therefore rebuilt every time the function runs.

Isolating it on one function whose body is a single folded template:

| | translate |
|---|---|
| cache expansion stubbed out entirely | 163 ms |
| native accessor called, no Lisp expansion | 170 ms |
| expansion through `match-case` | 505 ms |
| the same expansion dispatched on the head | 186 ms |

The native accessor costs 7 ms across seventeen calls. The Lisp expansion
costs 335 ms, and rewriting two `match-case` uses as `cond` on the head
recovers all but 23 ms of it. Across the thirty ported functions the same
rewrite moved 70 s to 62 s, because the lowering's own dispatches, which
are much larger, still go through `match-case`.

Two ways to fix it, and they are not exclusive:

- **In the prototype**, dispatch on the head in the hot paths. Mechanical,
  and `c._content` with sixteen clauses is the one that matters. It makes
  the lowering's own source worse to read, which is the cost.
- **In the interpreter**, memoize a macro expansion per call site. The raw
  argument forms at a site do not change, so the expansion does not either.
  This would speed every macro in compile-time Lisp, including
  `autodiff.xmacro`'s own `match-case` uses, and it is the fix that belongs
  in the compiler rather than in one caller. It needs care over macro
  redefinition and over macros that read mutable globals.

The 330x figure therefore measures a fixable interpreter cost that this
prototype happens to pay heavily, not the cost of lowering x2c to Lisp.

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

## Compiled pass: what it now lowers

`src/lower.x` carries the whole lowering. Beyond the int/double core it
handles:

- `match` statements, including patterns with binders and arms that are
  blocks. A folded pattern resolves through its cache; the arm binds each
  binder to the matched sub-form.
- Literal templates in expression position. A `cons`/`append` chain lowers
  part by part, so `%(sum $a $b)` builds the List at run time instead of
  being mistaken for a folded constant.
- The value types: `List`, `Var`, `String`, `Symbol`, `Map`, `Array`. A
  method call is an ordinary direct call into the name `etc/lisp-lower.xlisp`
  binds.
- Symbol literals, including operator spellings such as `<+>`.
- Lambdas passed to a value operation, with their free locals substituted by
  value.
- `void`, lowered to nil. A lowered function cannot tell `void` from an empty
  List; nothing in the ported code depends on that difference.

Mutual recursion needs a Lisp stub ahead of the definitions, the way a C
prototype does: `$(def ad_fwd_item (lambda (. rest) 0))`.

## Forward-mode autodiff through the compiled pass

`.context/spike/pass-fwd.x` is the whole of forward mode written as
compile-time x2c, installed by `$(x2c.comptime.install $fn)`. It derives
`square` and `poly` and both derivatives are exact:

    square_dot(3) = 7.0  expected 7.0
    poly_dot(2)   = 17.0  expected 17.0

Whole-build time against the interpreted spike over the same source:

| pass | build |
| --- | --- |
| interpreted (`.context/spike/autodiff-fwd.x`) | 3.11s |
| compiled (`.context/spike/pass-fwd.x`) | 0.30s |

The smaller declaration slice measures the same way: 0.80s against 0.08s.

## Reverse mode through the compiled pass

`unittest/compiler-fixtures/comptime-autodiff.x` carries the whole of `lib/autodiff.xmacro`'s
forward and reverse modes as compile-time x2c: the primitive derivative
table, the tangent rules, the adjoint rules, the tape, exit codes, the loop
trip counter and its dispatch, and both decorators. Every derivative it
produces matches a central finite difference:

    energy_grad  = 1.027917 0.201031   finite diff 1.027917 0.201031
    horner_grad  = 30.243600 16.863256 finite diff 30.243600 16.863256
    guarded_grad = 5.200248 5.672335   finite diff 5.200248 5.672335
    mixed_dot(1.3) = 12.146367         finite diff 12.146367

`horner` covers a `for` loop with a nested `if`; `guarded` covers a `while`
with `break` and `continue`; `mixed` covers `sin`, `exp`, `sqrt`, `log`,
`pow`, `fabs` and `atan2`. Installing about ninety compile-time functions and
deriving five siblings translates in 777 ms.

Checkpointed loops (`$ad.checkpoint`) and calls to an earlier differentiated
sibling are the two paths not ported.

## What the pass gained along the way

- Cells. A local whose address is taken, or one a loop assigns a call result
  to, lives in a one-slot box: `C.cell` allocates, `C.load` reads, `C.store`
  writes. `foreach`, out-parameters and `*p` all work through it. A cell a
  loop body declares is allocated once before the loop runs.
- The scan runs twice, so the second pass sees the cells the first found.
- A function's own name counts as bound, so self-recursion needs no stub.
- Interpolated strings (`%"$stem${n}"`) lower to `string-append`.
- An expression statement that is a call runs as an effect.
- `*` is a sequence binder in a pattern, so a unary deref is matched by arity
  and then by its operator. The same trap silently swallowed every `op` form
  the first time.
- A pattern that folding left unresolved, as a typed capture leaves it, now
  declines instead of being matched as raw AST. Before that, a `case` with a
  typed capture silently never fired.
- `List.assoc`, `List.get`, `List.getindex`, `List.last` and `Map.get` return
  `void` for an absent element, which has no Lisp value and aborts the
  session. Their bindings in `etc/lisp-lower.xlisp` answer nil instead.
