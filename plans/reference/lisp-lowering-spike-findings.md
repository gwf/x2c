# Spike: interpreting an x2c function AST in compile-time Lisp

> Status: reference - historical spike findings, retained for design evidence.
> The implementation is recorded in [the completed lowering plan](../archive/x2c-lowers-to-lisp.md).

Date: 2026-09-17.  Worktree: `x2c-ast-lisp-spike-e1785b`.  The spike files
here are uncommitted and `.context/` is git-excluded; the value surface the
spike motivated was landed separately and is described under "This is now
shipped".

## What was built

- `c-sdk.xlisp` (~200 lines) -- a C machine in compile-time Lisp: `C.if`,
  `C.while`, `C.for`, `C.do-while`, `C.switch`, `C.block` as macros, and
  storage, arithmetic, and calls as functions.
- `c-from-ast.xlisp` (~330 lines) -- `c.translate`, one `match-case` clause
  per AST production, producing a `C.*` program; `c.install` evaluates it.
- `arithmetic-and-control.x`, `memory-and-switch.x` -- 18 functions whose
  compile-time result is substituted back into the source and compared
  against the same function compiled and run natively. All 18 agree.

## The result

It works. A typed x2c function AST rewrites into a small C-emulation SDK
almost mechanically, and the emulated run agrees bit for bit with the
compiled one, including `int` wraparound, shifts, integer division,
short-circuit operators, `double` arithmetic, recursion, arrays, pointers
to locals, pointer arithmetic, and `switch` fall-through.

Three properties of the existing compiler carry most of the work:

1. A `Unit` decorator's capture is the **bound and typed** AST. Every
   identifier is `(binding ID "name")` with a unique id, so the emulator
   keys its frames by id and needs no renaming, scoping, or shadowing
   analysis. Every expression carries its type, so `int` and `double`
   behavior is chosen at translation time.
2. `Var.binary` is already a complete C operator: `+ - * / % & | ^ << >>
   == != < <= > >= && ||` with C integer promotion, width-correct
   wrapping, sign-filled right shifts, and C floating promotion. The Lisp
   reader produces `i32` for small integer literals and `f64` for
   floats, so the Lisp number tower *is* the C value model.
3. The AST grammar is regular enough that translation is one `match-case`
   clause per production, in the shape `agents/replacing-manual-ast-walks-
   with-match.md` already prescribes.

`long` and `long double` are less of a problem than expected. `Var`'s
numeric model has ranks and widths for every C integer type and for
`long double`, so the arithmetic exists. What is missing is a way to
*enter* those types from Lisp: the reader gives `i32`, `i64` (for literals
too large for `int`), and `f64`, and there is no bound conversion.

## x2c values need no emulation at all

Added after the first round. For code that uses `List`, `String`, `Var`,
`Map`, and `Array`, the C machine is the wrong frame. A value in a macro
Lisp session **is** an x2c Var: `(type (list 1 2 3))` answers `<list>` and
`(type "hello")` answers `<string>`. So the translation is not emulation,
it is a name table.

The typed AST does the rest. By the time a `Unit` decorator sees it, a
method call is already resolved to its runtime function:

    v.len()   ->  (call (expr ((func (("List"))) (int))
                        (ident (binding 83 "List_len"))) (args ...))

so the translator needs no method resolution. `runtime-bridge.xlisp` is
the whole layer: `List_len` -> `length`, `Var_car` -> `car`,
`String_len` -> `string-length`, `Map_getindex` -> `Map.getindex`. The
boxing converters (`int_var`, `String_var`, ...) are the identity, because
the Lisp value already is the Var the program would box.

Three productions were new and took about 30 lines: `(getindex RECV KEY)`
dispatched on the receiver's static type, assignment through it, and the
empty `{}` / `[]` initializers, which carry no type of their own and take
it from the declaration.

`x2c-values.x` runs four functions this way against native: a `List` walk
with `.len()/.car()/.cdr()/.reverse()`, `String.lower()` and `.len()`, a
`Map` word counter using `.contains()` and indexed read and write, and an
`Array` built with `.push()` and read by index. All four match.

Speed is also better here, because these operations are the real ones
rather than an interpreted loop over emulated memory.

### This is now shipped

The spike's private bridge became a real surface. `etc/lisp-values.xlisp`
names 69 library operations over `List`, `Array`, `Map`, `String`, `Var`,
and `Symbol`; `lib/lisp.x` gained the matching rows in
`lisp.native.target.rows`; and `src/macros.x` loads the layer into every
compile-time Lisp session. `Map.list` was added to `lib/list.x` because a
`Map` cursor has no Lisp representation. See the commit "reach the core
value types from compile-time lisp".

Two things made it cheap. `_lisp_resolve_type` already accepts `Var`,
`Symbol`, `String`, `List`, `Array`, `Map`, `File`, `Iter`, `Func`, and
the numerics, so no wrappers were needed; and `$lisp.bind` refuses an
ineligible signature at compile time with "native binding parameter type
has no Var representation", which names every method that cannot be
exposed. That diagnostic is how the member list was chosen: `char *`
parameters (`String.strip`, `Symbol.new`), pointer out-parameters, and
`Iter` cursors are out, everything else probed clean.

Loading the layer costs 0.16 ms per compile-time session, measured over
50 sessions against 0.39 ms for `etc/init.xlisp` alone.

`runtime-bridge.xlisp` in this directory now calls the shipped names
rather than its own `bind` rows.

## Where it breaks

**Natives with no Lisp binding.** As predicted, this is the real boundary.
The translator resolves every callee statically and refuses at translation
time with the function's name:

    macro: c-from-ast: call to a function with no compile-time binding
      note: "sqrt"

An SDK author registers one with `(C.native "abs" (lambda (v) ...))`. A
pure function can be written in Lisp; anything with an effect or a C data
structure cannot.

**Conversions between int and double.** Fixed by the shipped surface:
`Var.convert` narrows a `double` to an integer tag and `Var.parse` reads a
`String` as an `int`, `double`, `string`, `symbol`, or `char`. Before that
change neither was reachable.

**Returning a `double` to the source.** `str` formats with `%f` (6 decimal
places) and `repr` with about 16 significant digits. Neither is guaranteed
round-trip exact for `f64`; the spike's `newton` test failed under `str`
and passes under `repr` by luck of the value. Exact emission needs a
`%.17g` or hexadecimal float printer.

**Everything outside the supported grammar** fails with a named
diagnostic at the invocation: `goto`, labels, `struct` declarations and
field access, x2c collection types and their literals, `defer`, `foreach`,
`match`, `try`/`catch`. None of these are hard in principle -- `switch`
with fall-through took about 25 lines -- they are simply unwritten.

**Speed.** First measured with an association-list frame, then again after
the shipped `Map` made an in-place keyed store reachable:

| workload | alist frame | Map frame |
|---|---|---|
| 20,000 loop iterations | 7.26 s | 2.57 s |
| 100,000 loop iterations | 37.4 s | 14.67 s |
| 20,000 iterations, 12 extra locals | 28.1 s | 2.92 s |
| `fib(20)`, 21,891 calls | 28.1 s | 21.55 s |
| `fib(24)`, 150,049 calls | 219.7 s | 188.6 s |

The alist frame was walked and rebuilt on every assignment, so cost grew
with the number of locals: twelve unused locals made the same loop 3.8x
slower. With a `Map` that penalty falls from +287% to +14% and loops run
2.5-9.6x faster.

Calls barely moved, which locates what is left. At roughly 6,800 loop
iterations and 1,000 calls per second the cost is no longer the data
model; it is the Lisp evaluator's own apply and frame machinery, plus one
`Map` allocated per activation. Anything faster needs a different
execution substrate, not a different data structure.

A second structural constraint: the evaluator reuses a frame only for a
**direct self tail call**. The first loop driver put its recursive call
inside `(begin (step) (C._loop ...))`, which is an argument position, and
a 200,000-iteration loop grew to 280 MB before it was killed. Rewritten so
the recursive call is the last `cond` consequent of `C._loop` itself, the
same loop runs in constant memory and linear time. Any Lisp that drives C
control flow has to be written this way.

## A compiler defect found on the way

A `Unit` decorator that returns its captured function unchanged from
compile-time Lisp fails to parse when the body contains `*=`. No other
compound assignment fails. Minimal reproduction:

```x2c
#include "x2c.x"
$(defun identity (fn) (list fn))
macro Decorator $d(Unit $fn) => { $(identity $fn)... }
$d()
int f(int x) { x *= 3; return x; }
int main(void) { return f(1) != 0; }
```

    parse: expected syntax

`x += 3`, `x /= 3`, `x %= 3`, `x &= 3`, `x |= 3`, `x ^= 3`, `x <<= 3`,
`x >>= 3`, `x = x * 3`, and `x++` all pass through the same path. The
likely cause is that a Lisp-returned List is re-read as macro syntax and
the bare symbol `*=` is taken for a `*` sequence binder.

## Smaller things worth knowing

- A decorator production may not be empty. `$(f $fn)...` where `f` returns
  `nil` is reported as `parse: expected syntax`, with the Lisp diagnostic
  lost. Returning `(list fn)` and dropping `$fn` from the template works.
- In compile-time Lisp an operator symbol must be spelled `'<"+">`. `'<+>`
  reads as a Symbol whose text is the four characters `<+>`, and inside a
  `.x` file a bare `<<` makes the x2c scanner swallow the rest of the form
  looking for the closing `>`.
- Literal text arrives as source spelling: `(literal (int) "42")`,
  `(literal (* char) "\"abc\"")`. There is no string-to-number binding, so
  the SDK parses digits itself. Decimal integers and floats with an
  exponent are about 40 lines; hex, octal, character literals, and suffixes
  are not written.
- `autodiff.xmacro` is the working precedent for all of this and was the
  most useful file to read first.
