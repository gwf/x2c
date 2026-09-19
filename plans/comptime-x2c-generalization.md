# Comptime x2c generalization

> Status: active
>
> Scoped 2026-09-18 on branch `x2c-lowers-to-lisp` after the autodiff port
> landed. Phases 0-4, 6 and 7 are done or answered; 5 ported two of its three
> files and declined `lib/var-tags.xmacro` on evidence.
> `plans/meta-functions.md` carries the `meta` keyword work: M1, M2, M5, M6
> and M7 built, M3 and M4 declined on evidence, M8 scoped and not built.
> `tools/gate-state.py ensure agent-pr-check` passes on this branch. Nothing
> on this branch reaches `main` without Gary's explicit green light. The
> design in `plans/x2c-lowers-to-lisp.md` is settled and this plan does not
> revisit it.

## The objective, set 2026-09-18

**Replace essentially all hand-written compile-time Lisp with `meta`
functions.** If it does not need to be Lisp, make it `meta`. Three exemptions
and no others:

1. **The irreducible core** that lowered code is written in: the special forms
   `lambda`, `cond`, `quote`, `begin`, `def`, and the natives the lowering
   emits - `car`, `cdr`, `cons`, `list`, `append`, `match`, `eq?`, `not`, and
   arithmetic. A meta function cannot be written in itself.
2. **The name tables** that map a lowered call to an operation:
   `etc/comptime.xlisp`, `etc/lisp-bindings.xlisp`, `etc/lisp-values.xlisp`,
   `etc/lisp-io.xlisp`. These are a dictionary, not logic.
3. **Anything an attempt shows to be genuinely problematic**, with the
   evidence recorded. M3, M4 and Phase 7 are the existing examples; each
   records what was measured and why the answer was no.

Everything else is a candidate, including the parts of `etc/init.xlisp` and
`etc/builtin-macros.xlisp` that earlier revisions of this plan called
permanent. M7, callable values, is built; M8, installing a compile-time
function at session start, is scoped and not built, and is what still gates
the rest. Both are in `plans/meta-functions.md`.

Nothing here is done for speed. Measured, a rewrite is neutral on the call
side because a Lisp `defun` is word-compiled too, and costs about 0.31 ms per
declaration per importing unit. The case is readability.

## The result

A compile-time function written in x2c can use the language the way the rest
of the compiler uses it: collection literals, indexing, the ordinary control
flow, and iteration over any container. When that is true, the macro Lisp
that exists only because Lisp was the only compile-time language can be
rewritten as x2c, and the lowering pass compiles it to the same Lisp the
evaluator and word machine already run.

The measure of done is not a line count. It is that a reader can open a
compile-time function and see ordinary x2c, and that the remaining Lisp in
the repository is there because it is the substrate (`etc/init.xlisp`), a
name table (`etc/lisp-bindings.xlisp`, `etc/lisp-values.xlisp`,
`etc/comptime.xlisp`), or a macro template with no Lisp body at all
(`lib/array-generics.xmacro`, `lib/map-generics.xmacro`).

## Where the work stands

`src/comptime.x` translates a compile-time x2c function into Lisp, and
`etc/comptime.xlisp` is the runtime that translated code calls. They were
`src/lower.x` and `etc/lisp-lower.xlisp` until 2026-09-18; the old pair read
as if both lowered Lisp, when only one of them lowers anything and the other
is a runtime. The stem-pair convention follows `lib/varops.x` +
`lib/varops.xlisp`. Together they already carry: `if`, `while`, `for`, `match` with
binders and block arms, literal templates, direct and self recursion,
lambdas passed to a value operation, cells for address-taken and
loop-assigned locals, `foreach` over a `List`, pointer deref and store,
interpolated strings, file-scope state, and the `List`/`Var`/`String`/
`Symbol` operations named in `etc/comptime.xlisp`.

The whole of forward and reverse mode from `lib/autodiff.xmacro` is ported
in `unittest/compiler-fixtures/comptime-autodiff.x`: 111 compile-time
functions, every derivative checked against a central finite difference, and
751 ms to install them all and derive five siblings. Forward mode alone
measures 0.30 s of whole-build time against the interpreted spike's 3.11 s.

Macro Lisp in the repository, measured 2026-09-18 by counting lines inside
`$(...)` forms:

| file | Lisp lines | disposition |
| --- | --- | --- |
| `lib/autodiff.xmacro` | 754 | ported (Phase 6 decides whether it replaces the original) |
| `etc/builtin-macros.xlisp` | 504 | stays Lisp; Phase 7 answered it |
| `lib/var-tags.xmacro` | 295 | Phase 5 declined it; see below |
| `etc/init.xlisp` | 237 | substrate, stays |
| `etc/comptime.xlisp` | 121 | name table, stays |
| `etc/lisp-bindings.xlisp` | 119 | name table, stays |
| `etc/lisp-values.xlisp` | 97 | name table, stays |
| `etc/compiler-sdk.xlisp` | 43 | Phase 5 decides |
| `etc/lisp-extras.xlisp` | 34 | Phase 5 decides |
| `lib/system-macros.xlisp` | 145 | Phase 5 |
| `lib/varops.xlisp` | 57 | ported; the file is gone |
| `lib/error-macros.xmacro` | 32 | a data table, not logic |
| `lib/error-private.xmacro` | 20 | `x2c.ident` calls in a macro body |
| `lib/system-macros.xmacro` | 8 | an import and two call sites |
| `etc/lisp-io.xlisp` | 5 | stays |

Counting lines overstates the three name tables. Of the 78 definitions in
`etc/comptime.xlisp`, 46 are one-symbol aliases such as `(def List_len
length)` and 10 are identity conversions such as `(defun int_var (v) v)`,
because a Lisp value in a macro session already is an x2c `Var`. Only about
20 carry any logic, and those exist to give an x2c operation a Lisp meaning
rather than to implement anything. The same holds for `etc/lisp-bindings.xlisp`
and `etc/lisp-values.xlisp`. Read the 337 lines across those three files as a
dictionary, not as work.

Fifteen everyday constructs were probed against the pass on 2026-09-18.
Fourteen declined. That gap, not the remaining Lisp, is what blocks the
general case. Phases 1 and 2 have since closed the collection and control
flow parts of it.

## Working agreement

Every phase happens on a branch off `x2c-lowers-to-lisp` and merges back into
it, never into `main`. Phases 1-4 all edit `src/comptime.x`, so each names the
functions it owns; an agent that needs to change a function another phase
owns says so in its branch rather than editing it silently.

Each phase ends by adding its probes to `comptime-lowering.x` and running
`make verify-fixtures`, so a phase that regresses another phase's construct is
caught before it merges. Never run `make verify-fixtures-update` to make a
failure go away; it rewrites the expectations.

## Phase 0 - a tracked probe fixture (done)

The probes lived in `.context/spike/`, which is excluded by
`.git/info/exclude`, a local file that does not travel. Worse, those files are
untracked working files, so no other worktree of this repository had them
either: a fork of this branch, local or pushed, arrived with the pass and the
plans but without a single thing that exercises them. Three fixtures now carry
that evidence in the repository.

- `unittest/compiler-fixtures/comptime-lowering.x` (`stdout status`) holds one
  `$comptime()` function per construct the pass carries and calls each in
  expression position, so the printed value is what the lowered Lisp produced
  during translation. This is the ledger every later phase extends.
- `unittest/compiler-fixtures/comptime-declines.x` (`compile-status
  diagnostics`) holds `goto`, the one permanent refusal. A refusal stops
  translation at the first function, so each deliberate decline needs its own
  fixture; the phase that introduces one adds it.
- `unittest/compiler-fixtures/comptime-autodiff.x` (`stdout status`) is the
  autodiff port, printing a tolerance verdict per derivative rather than
  digits so the expectation is stable across platforms.

`plans/reference/lisp-lowering-values.xlisp` is the interpreted spike's
value-type handling, kept because it is the only worked example of the
`getindex` and collection-literal lowering Phase 1 needs;
`plans/reference/lisp-lowering-spike-findings.md` is the original spike
write-up. The rest of `.context/spike/` is superseded by `src/comptime.x` and
`etc/comptime.xlisp`.

A calling convention worth knowing: a bare `$(fn args)` in expression position
folds a compile-time result into the program, which is how the fixtures report.
It accepts integers and strings; a `double` result needs `$(str (fn args))`.

## Phase 1 - collection literals and indexing (done)

Landed as `6e5cec84` and `47f9653a`. Array literals, map literals, bracket
reads on `Array`/`List`/`Map`/`String`, bracket writes to `Array` and `Map`,
local C arrays, and the conversions a declaration and a return need. The
nineteen new lines in `comptime-lowering.stdout` are the evidence.

Three corrections to what this section said before the work, each checked
against `--dump-ast` from a decorator:

- **An array literal lowers to an `Array`, not to a Lisp `List`.** The rule
  below said the opposite, and it is wrong: `g([n])` is legal x2c, and an
  array literal in an argument position has no destination for the pass to
  read, so lowering it as a `List` hands a callee that declared `Array` the
  wrong container with nothing to catch it. The conversion goes the other
  way, at a `List` destination.
- **`{}` is not `(map)`.** It is `(composite (commas))` and its node carries
  no type at all, so only the destination can decide what it builds. Only a
  non-empty map literal is `(map (map-entry k v)...)`.
- **A bare name left of `:` is a `Symbol` key**, not a variable reference.

Two conversions the pass has to make itself, because the pre-transform tree
does not carry them: a declaration and a return. An assignment does carry
its conversion already, so it needs nothing. `_lower_coerce` owns all of it
and covers `Array`/`List` both ways and `Symbol` to `String`; the last pair
was a segfault, because a compile-time function returning `Var.tag` folded a
`Symbol` into a `%s` slot.

Two defects fixed in passing. `Var zero = type.match(...) ? 0.0 : 0;` promotes
both branches to `double` in C, so every uninitialized local was lowering to a
floating zero. And `if (!values)` on an `Array` tests emptiness, not failure,
so an empty initializer read as an error.

Still refused, deliberately: compound assignment through an index
(`xs[0] += 5`) declines as "update of a computed place", because a
read-modify-write through one place is more than place analysis; an indexed
write to a `List` or `String` declines, since `List` has no `setindex`; and a
computed array dimension declines.

Two files outside this phase changed, as the working agreement requires an
agent to say. `etc/comptime.xlisp` (Phase 3) gained `String_getindex`, a
`Map_of` constructor, and bounds-checked `Array_getindex`/`Array_setindex`,
without which the first out-of-range read aborts the session on a `void`
crossing. `_lower_stmnt`'s `return` case (Phase 2) now coerces, without which
a `List`-returning function that accumulates into an `Array` returns the
`Array` silently.

The original scope follows.

Owns `_lower_content`'s value productions, `_lower_store`'s place analysis,
and the `array`/`map`/`composite`/`commas`/`getindex`/`index` entries in
`_lower_scan`.

The largest gap and the one that changes how ported code reads. Today
`unittest/compiler-fixtures/comptime-autodiff.x` contains eighteen hand-rolled
recursive list builders that exist only because there is no `Array` with
`push`, and `ad_partial` is a twenty-seven-branch `if (name.equal("sin"))`
chain that wants to be one `Map` lookup.

**Start by reading the right AST.** A `Unit` decorator captures the
**pre-transform** tree, so the pass sees `(array e...)`, `(map (map-entry k
v)...)` and `(getindex receiver index)`. It does not see the `varray`, `vmap`,
`vpair` forms or the `int_var` element conversions that `--dump-transforms`
shows; those are inserted after the pass has run. Do not design against a
transformed dump.

**The type on the literal is not the type of the destination.** `[a, b]` is an
array literal: its node type is `("Array")` whether it initializes an `Array`
or a `List`. After transform the compiler bridges that with an `Array_list`
call, but the pass never sees that call and must apply the conversion itself.
The rule:

- `(array e...)` lowers to `(list e'...)`, a Lisp List, since a Lisp List is
  the direct representation of a sequence of lowered elements.
- Where the destination type is `Array`, wrap that in `List.array`, which is
  already bound as `List_array` in `etc/comptime.xlisp`. Where it is `List`,
  emit it bare. The destination type is on the `declare` for an initializer
  and on the assignment target otherwise.
- No element conversion is needed in either direction. A Lisp value in a macro
  session already is an x2c `Var`, which is why ten of the conversions in
  `etc/comptime.xlisp` are the identity.
- `(map)` lowers to `(Map.new)`; `(map (map-entry k v)...)` lowers to a
  `Map.new` followed by one `Map.setindex` per entry. Decide during the work
  whether that reads better as a `Map.of` helper in `etc/comptime.xlisp`;
  either is acceptable, a second representation is not.
- `xs[i]` dispatches on the receiver's type, not a guess: `List.getindex`,
  `Array.getindex`, `Map.getindex`, `String.getindex`.
  `plans/reference/lisp-lowering-values.xlisp` did exactly this in
  `c._getindex`; carry that dispatch in.
- `m[k] = v` is the `index` production in a store position and becomes
  `Map.setindex` or `Array.setindex` by the same dispatch.
- A local array `int a[4] = {...}` becomes a cell holding an `Array`, reusing
  the machinery this branch already built; `a[i]` then reads the box and
  indexes it. This removes the `arrays` decline entirely.

Everything this needs is bound in `etc/comptime.xlisp` already.

## Phase 2 - control flow (done)

`break`, `continue`, `do`/`while` and `switch`. The eleven new
`$comptime()` functions in `comptime-lowering.x` and the ten new lines in
`comptime-lowering.stdout` are the evidence, plus the new
`comptime-declines-fallthrough` fixture.

`break` and `continue` are continuations, carried in `Lowering` beside
`on_loop`. `continue` is the loop's own `(again ...)`. `break` needed an
exit the body can reach from anywhere, so a loop whose body contains one
also defines its `leave` as a function over the same live locals and calls
it; a loop without a `break` still inlines `leave` into the `cond`. That is
the only lasting new mechanism, as the plan review predicted.

Four corrections to what this section said before the work.

- **`do`/`while` is not a `while` with a first-iteration flag.** A flag
  needs a local, and the pass has no binding id to give it: `_lower_target`
  returns `-1` for "not a plain local", so synthetic negative ids read as
  computed places, and a synthetic positive id can collide with a real one.
  `do BODY while (TEST)` is instead `while (1)` with
  `if (TEST) ; else break;` as the loop's **step**, which is exact and needs
  nothing new.
- **A `for`'s step had to move out of the body.** It sat at the end of the
  body because the subset had no `continue`; with `continue` it would be
  skipped. Both loops now carry a step, reached by the body's end and by
  every `continue`, through one continuation form `(then steps next break)`.
- **That continuation has to carry the `break` in force where it was
  written.** Without it, a `switch` inside a `do`/`while` recursed forever:
  the arm's `break` reached the switch's exit, which reached the loop's
  step, whose `break` found the switch's exit again.
- **An arm ending in `continue` is not fallthrough**, and the last arm of a
  `switch` needs no `break`, since nothing follows it to fall into.

`switch` lowers to one `cond` over a subject that is bound only when
`_lower_pure` says it cannot be repeated; a `default` anywhere becomes the
final clause, and labels with no statements between them share one arm.
Fallthrough declines, as decided. `goto` still declines from the scan, now
with a reason that names it rather than "unsupported construct", so
`comptime-declines.diagnostics` changed.

One gap this phase leaves: a `switch` whose subject needs a binding and
which sits on a loop's iteration path declines, because the binding would
cost the loop its frame reuse. In practice that is a `switch` on a call
result inside a loop, which Phase 5 and Phase 6 will meet. Hoisting such a
subject into a cell allocated before the loop, the way `_lower_loop_cells`
already hoists a body's cells, is the shape of the answer; it was out of
scope here and has no caller yet.

One defect fixed in passing, outside this phase's functions. `_lower_name`
numbered from zero per function, so two compile-time functions with the same
parameter count defined the same `loop2` in the one shared macro session and
the second silently replaced the first. Two loops that only differ in their
body returned the same wrong answer. Generated names now carry the function
they belong to.

## Phase 3 - the mechanical gaps (done)

Landed on `comptime-phase3-mechanical`. Destructuring declarations,
`foreach` over a `Map` and an `Array`, and the two deliberate refusals.
Ten new lines in `comptime-lowering.stdout` and two new decline fixtures,
`comptime-declines-defer` and `comptime-declines-struct`, are the evidence.

Four corrections to what this section said before the work, each checked
against `--dump-ast` from a decorator:

- **A destructuring declaration is not a declarator.** It is its own
  statement, `(dstrdecl TYPE (targets (binding id name)...) SOURCE)`, so the
  case is in `_lower_stmnt`, which Phase 2 owns. There is a second spelling,
  `(int a, String b) = pair`, which parses as `(dstrdecl (params ...)
  SOURCE)`; the repository writes both, so both lower through one
  `_lower_destructure`.
- **The elements are `List.getindex`, not `car` and `cadr`.** The transform
  converts the source to a `List` and reads position `i` out of it, so the
  lowering converts with `_lower_coerce` and reads the same way. That also
  gives a short source a nil element instead of a `void` crossing.
- **A destructured target is not a `bind` node**, so the scan had to learn to
  register those ids as locals. Without that a later write to one lowered to
  `C.gwrite`, treating it as file-scope state.
- **`Map_try_next` takes four arguments, not three**: object, cursor, key and
  value. `foreach (Var v, m)` binds the one name to the *value*. `Array` uses
  a counting cursor and one output; `List` walks a cursor that holds the
  remaining list.

One defect fixed in passing, reproduced first at `ea3d955d`. Generated names
restarted their counter with each function, so two compile-time functions of
the same shape named their loops alike and the second `def` silently replaced
the first. Everything a fixture could show was already wrong: adding a second
loop-bearing function broke `ct_accumulate`. The counter now runs across the
session and `Lowering.counter` is gone.

Still refused, deliberately: `defer` and any struct or union, each with its
own wording and its own fixture. Refused for want of work: a destructured
local that needs a cell, and a destructuring on a loop path whose source is
not duplicable, which is the rule every other initializer already follows.

The original scope follows.

Owns `_lower_declarator`'s tuple case and `etc/comptime.xlisp`.

- `Var (a, b) = pair` binds each name to `(car p)` and `(cadr p)`, holding
  `p` once when it is not pure.
- `foreach` over a `Map` or an `Array` needs `Map_try_next` and
  `Array_try_next` shims beside the `List_try_next` that already exists.
  Check the generated AST for each: the `List` form takes object, cursor and
  output, and the others may differ.
- `defer` declines, with a diagnostic saying a compile-time function does not
  free its values because the evaluator owns them. This is a deliberate
  limit; `Array a = []; defer a.free();` is correct x2c and wrong comptime
  x2c, so the refusal has to explain itself rather than say "unsupported".
- Struct locals and field access stay out of scope. A struct would have to
  become a `Map` keyed by field name, which changes value semantics. Say so
  in the declines fixture.

## Phase 4 - typed captures in patterns (done)

Owned `_lower_arms` and whatever in `src/literals.x` the investigation found.
`_lower_arms` needed no change; six lines in `_build_cons_cell` were the fix.

**The question the phase was given has a negative answer.** A typed capture
must not fold to the plain capture atom. `?(String n)` is not only an
annotation on the binder: `_parse_typed_capture` and
`Compiler.typed_match_pattern` expand it into `(!is ?n type <String>)`, which
`lib/match.x` normalizes to
`(!set ?n (!is type <String>))` - bind the element and test its `Var` tag.
Dropping the type would make `case %(call ?(String n))` fire on `(call 42)`,
which is the silent wrong answer the decline exists to prevent. Any future
work here must keep the guard in the folded value.

**The pattern folds anyway, guard included.** For a concrete type
`Compiler.var_tag_expression` returns a `Symbol` literal, so every part of
the expansion is constant. What stopped it was mechanical. Typed captures
are parsed as bare `?n` atoms with their types recorded in `match_types`,
and `Compiler.typed_match_pattern` re-expands them afterwards, rebuilding the
cons chain through `_build_cons_cell`. That builder converted each nested
`List` head to `Var` before offering the cell to the cache, and a `List_var`
call is not a shape `Compiler.cache_cons_cell` can represent, so the first
rebuilt head broke folding for the whole pattern. Caching a folded nested
`List` head as its own `(var ...)` key first - which is exactly what
`_parse_list_head` does for a parsed element - restores it. No second folding
path, and no new representation: the rebuilt pattern now reaches the cache
the way a parsed one always did.

Measured with `--dump-ast` from a `Unit` decorator: `case %(call ?(String n))`
was a four-deep `cons` chain around a `List_var` call and is now
`(expr ("List") (expr ("List") (cache 14)))`, the same shape the untyped
`case %(call ?n)` already had.

**The decline stays and is still reachable.** A pattern that interpolates a
run-time local, `case %(call $x)`, still declines with "case pattern is not
folded". That is the decline doing its job; it was never specific to typed
captures.

Five constructs are in `comptime-lowering`, each called twice so the
fallback proves the tag test survived folding: a `String` capture, an `int`
capture, a capture inside a sublist, a typed and an untyped capture in one
pattern, and a `Symbol` capture. The same five functions compiled as ordinary
run-time x2c print the same ten answers.

Four checked-in artifacts changed, each read before it was accepted.
`match-typed-flat.c` and `braced-unquote.{ast,transform,c}` now intern the
folded lists their literals had been rebuilding at run time. The generated
`classify` body in `match-typed-flat.c` is byte-identical and every `.stdout`
and `.status` passed unchanged, so only the file-init constant table moved.
Typed patterns now intern the whole pattern the way untyped patterns already
did, which is consistency rather than a new cost.

One file outside this phase changed, as the working agreement requires an
agent to say: a four-line comment in `_lower_constant_leaf` (`src/comptime.x`)
named the typed capture as its example of an unfoldable node, which is no
longer true.

## Phase 5 - port the remaining macro Lisp (done; var-tags declined)

`lib/system-macros.xlisp` is ported: 12 of its 13 `dedent.*` definitions are
now four `meta` functions in `lib/system-macros.xmacro`, the file went 145 to
69 lines, and `unittest/test-system-macros.x` passes unchanged. Measured cost
+19 ms, of which +12 ms is the `foreach` spelling over the `replace` spelling
it replaced; the loop was kept because it reads better, which is the trade this
phase exists to make.

`lib/varops.xlisp` is ported and the file is gone. Its 14 rows, five row
accessors and two expression builders are ten `meta` functions in the new
`lib/varops.xmacro`, and the one SDK shape it needed that M6 had left out,
`x2c.expr.cast`, is now `Meta.expr_cast`. The evidence is the generated C:
`bootstrap/lib/varops.c` and `builds/0/lib/varops.c` differ only in
error-site line numbers, every one by the same three lines the file grew, and
every generated body is byte-identical. Measured cost +2 ms on the one unit
that imports it, the minimum of six interleaved pairs.

Two things that port established for anyone doing the next one. A `.xmacro`
holding `meta` functions that call `Meta` must be imported **after** the unit
includes `lib/meta.x`, because the import borrows the unit's symbol table.
And a `meta` function anywhere in `lib/` needs the checked-in bootstrap to
carry the comptime lowering first; see "Capability before callers" below.

`lib/var-tags.xmacro` is **declined on evidence**, recorded below.

### Why `lib/var-tags.xmacro` stays Lisp

Attempted twice on 2026-09-18 and reverted both times. The obstacle is not
the file, and it is not an ABI question: it is where in the runtime the
ledger is consumed.

**A `meta` function that reads a table needs `Array.push` and
`List.getindex`, and every module that projects the ledger sits below those
types.** Reproduced against `builds/0` in three of them, each reporting
`type ("Array") has no method push`:

- `lib/common.x` is the base module, so nothing exists at any point in its
  parse: the import fails at line 18 and still fails at line 614, beside the
  `$var.tag.unbox` invocations that use it.
- `lib/var.x` declares `Var` itself, and `lib/array.x` and `lib/list.x`
  include it, so they are above it by construction.
- `lib/dispatch.x` is the same, and adding `#include "array.x"` immediately
  above the import does not help, because that include is a cycle and
  resolves to nothing.

Only `lib/varconvert.x` and `src/type.x`, the two highest consumers, could
host one. The ledger has five importers, not the four this plan recorded:
`src/type.x` projects `$var.tag.constant.rows()`.

**The second attempt was the ABI route and it does not reach the wall.**
Gary authorized moving the nine `$var.tag.unbox` accessors out of
`lib/common.x` on 2026-09-18: make them non-inline, define them in a proper
home, and leave the forward declarations in `common.h` so the 46 to 48 units
that call `Var_list` and `Var_string` still compile. That is a better shape
than the split this plan first tried, and it does free `lib/common.x` -
which matters, because `common.x` calls `Var_array` itself in the protocol
adapters it generates, so the accessors could never simply leave. But
`lib/var.x` and `lib/dispatch.x` still project the ledger for their own
tables, and they hit the same wall. Freeing `common.x` alone buys nothing.

**A third wall stands behind both.** `lib/common.x` cannot include
`lib/meta.x`: `meta.x` includes `common.x`, so the include is a cycle and
`lib/varconvert.x` then fails to parse `Symbol Var.integer_tag(int rank,
...)` because `Symbol` is never declared. Including `meta.x` late enough in
`common.x` does work, and costs one `#include "meta.h"` in `common.h` -
which puts `Meta` in the implicit prelude and makes it a reserved type name
in every program. `plans/meta-functions.md` states the opposite under
"Compatibility".

Two smaller obstacles are recorded for whoever revisits it. `_x2c.symbol-set`
is a private native with no `Meta` spelling by M6's decision, so
`$var.tag.symbolset` and `$var.tag.numeric.symbolset` would stay Lisp in any
case. And the ledger owes its callers one diagnostic, "unknown Var tag".

What both attempts did establish, in case the wall comes down: the table
transcribes cleanly into one literal template, `<ldouble**>` round-trips
through a `Symbol` without truncating, a hex literal in a template is an int,
a Lisp symbol from a `$(def ...)` table compares equal to an x2c `<symbol>`
literal, and a `meta` function can take that table as an argument from the
macro body, so the data need not be reachable by name.

**What would reopen it.** A `meta` function whose body reaches no collection
operation, or moving the collection types below `Var`. Neither is a port.

### Why this section used to say blocked


**Blocked, and the capability is now planned in `plans/meta-functions.md`.**
That plan's M2 adds the import-loop branch this phase needs. One correction to
what follows: the branch does not need to emit nothing. `x2c.comptime.install`
already returns `%($fn)`, so a compile-time function is emitted as a native
function today, and emission from an import is the ordinary header problem.

**Blocked on a missing capability, established 2026-09-18.** There is nowhere
to put a compile-time function that a shipped macro can rely on. Three probes,
all against the merged pass:

- A `.xmacro` cannot hold one. `$ct()` above a function definition inside a
  macro import fails with `unexpected form in macro import`; a macro import
  carries macro definitions and `$(...)` Lisp, not x2c function definitions.
- `#include` of a `.x` that defines one does not install it. The including
  unit reports `(unbound (name shout_width))`, so an include does not run the
  decorator.
- What does work is the consuming unit defining it: a macro imported from a
  `.xmacro` calls a compile-time function the consuming unit installed, and
  returns the right answer. That is the only shape available today.

So the campaign reaches Lisp inside a translation unit, which the autodiff
port demonstrates, and not Lisp inside a shipped macro library, which is
where all 497 remaining lines live. `lib/system-macros.xlisp`,
`lib/varops.xlisp` and `lib/var-tags.xmacro` are each the body of a macro
every consumer imports; requiring each consumer to define the functions first
would change their public surface, which the phase forbids.

This is Phase 7's ordering finding one level down, and it generalizes: the
blocking capability is installing a compile-time function from a shipped
library. Three candidate routes, none built, none costed:

1. The compiler sub-translates a named `.x` at import time.
2. `#include` runs a decorator in the including unit.
3. A `.xmacro` form carries x2c function source for the compiler to translate.
   There is no SDK binding that parses x2c text into an AST today;
   `x2c.source.text` goes the other way.

Route 1 is the same mechanism Phase 7 wanted for `etc/builtin-macros.xlisp`,
so one capability unblocks both. Decide it before scheduling this phase.

### The economics, measured 2026-09-18 after M2 unblocked it

Porting a shipped macro's Lisp body to meta functions is a **translation-time
regression**, and the case for doing it is readability rather than speed.

| | Lisp | meta |
| --- | --- | --- |
| declaring 44 accessors | +1 ms | +20 ms |
| per call, accessor work | 0.075 ms | 0.075 ms |
| autodiff, per derivation | 581 ms | 79 ms |

Per-call cost is identical for ordinary work, because a Lisp `defun` is
word-compiled by `_auto_analyze` just as a lowered meta function is. The
autodiff win is real but specific: it comes from the generated Lisp being
better than the hand-written Lisp there - `match` compiled once instead of
`match-case` re-expanded per call - not from x2c being faster than Lisp.

**The declaration cost was more than halved on 2026-09-18**, and the number
above is superseded. The cost was never the install: it was parsing each
definition and lowering it again in every importing unit, in both of that
unit's passes. `src/comptime.x` now keeps the lowered forms for the process,
so a file's function lowers once however many units import it.
`plans/meta-functions.md` records the split, what makes the forms safe to
share, and the measurements.

**Corrected twice, 2026-09-18.** An earlier version of this section put the
importer counts at 32 and 9. Both were wrong by about eight times: the grep
behind them counted copies under `unittest/build/`, which are build artifacts,
and a file's own comment. The real counts are:

| library | importers |
| --- | --- |
| `lib/var-tags.xmacro` | 4 - `lib/common.x`, `lib/dispatch.x`, `lib/varconvert.x`, `lib/var.x` |
| `lib/varops.xlisp` | 1 - `lib/varops.x` |
| `lib/system-macros.xmacro` | 1 - `unittest/test-system-macros.x` |

And the per-declaration cost is now 0.31 ms, down from 0.56 ms, after the
process-wide lowering cache in `plans/meta-functions.md`. A Lisp `defun` costs
0.04 ms.

Together those two corrections change the conclusion. Applied to the
candidates:

- `lib/var-tags.xmacro`: 44 functions over 4 importers, about **55 ms**, not
  the 630 ms the wrong counts implied.
- `lib/system-macros.xlisp`: measured at **+11 ms** on the one unit that
  imports it.

Phase 5 costs tens of milliseconds, not hundreds. That is small enough that
readability decides it, which is what the phase was always for. The
autodiff-shaped win needs a body whose Lisp was doing something expensive and
neither candidate has that shape, so do not expect a speedup - expect a wash.

### Two defects the first port found

**`foreach` inside a `.xmacro`: fixed.** A `meta` function in a macro import
that iterated a `List` or `Array` reported `type ("List") is not iterable`,
while the identical body in a `.x` unit ran. The cause was not a missing
shared field: `_shallow_parse_loop` opens with `rebuild_protocols(NULL)` and
an empty `conforms` because collection parses no bodies - except a `meta`
definition in an import, which is the one body it does parse. The import now
installs the protocols visible to it on first use. `List`, `Array` and `Map`
all iterate. A `Var` collection still declines, because its expansion needs
`Var_iter` and `Iter`, neither of which has a compile-time representation;
write the concrete type.

That fix matters out of proportion to its size, because `foreach` is the
iteration idiom and without it the `dedent` port had to spell "strip the
prefix from each line" as a `replace` over the whole text - the one function
in that port that came out worse than its Lisp. It should be rewritten as a
loop now.

### Original scope, for when it is unblocked


Depends on Phases 1-3. `lib/var-tags.xmacro` at 295 Lisp lines is the real
one; the error and system macros are small. `etc/compiler-sdk.xlisp` and
`etc/lisp-extras.xlisp` are judged during this phase: some of their contents
are name tables and stay.

Each port keeps the macro's public surface identical and is verified by the
suites that already cover it, not by new tests written for the port.

Phase 7 took `etc/builtin-macros.xlisp` out of scope. Re-counting what is
left, on 2026-09-18, changed the picture twice over. The original inventory
covered `lib/*.xmacro` and `etc/*.xlisp` and so missed two files that are
neither: `lib/system-macros.xlisp` (145 lines, 22 definitions) and
`lib/varops.xlisp` (57 lines, 10 definitions), each imported by its own
`.xmacro`. Being per-unit macro bodies rather than session libraries, they do
not have Phase 7's ordering problem at all, which makes them the easiest
targets here.

Against that, three files counted before hold no logic to port:
`lib/error-macros.xmacro` is one `$(def ...)` data table of cause names,
`lib/error-private.xmacro` is `x2c.ident` calls inside a macro body, and
`lib/system-macros.xmacro` is an import and two call sites.

So the phase is about 497 lines of real logic: `lib/var-tags.xmacro` at 295,
`lib/system-macros.xlisp` at 145, `lib/varops.xlisp` at 57.

Start with `lib/system-macros.xlisp`. Its 22 definitions are the `dedent`
implementation - `substring`, character tests, line splitting, prefix
stripping - which is string processing written in Lisp because Lisp was the
only compile-time language. It is the clearest case in the repository for
what this campaign is for, and x2c's `String` operations already say all of
it directly. `lib/varops.xlisp` is next: a data table plus row accessors,
the same shape as `var-tags` and a smaller rehearsal for it.

**One construct to know about before starting, scoped 2026-09-18.**
`var-tags` passes procedures as values: `var.tag.map` and `var.tag.filter`
each take one. Calling a `Func` held in a parameter does not lower, and
binding a name for it would not help, because `f(v)` is not a call in the
AST at all. It expands to a statement-expression that declares a `FuncArg`,
probes the reference type through `x2c_func_reference_type`, takes the
address of the argument, and only then reaches `Func.apply` - the whole C
calling convention, with struct locals and address-of. Reproduce it with
`Var call1(Func f, Var v) { return f(v); }` under a `$c.show` decorator.

The port does not need it. `var.tag.map` and `var.tag.filter` are `map` and
`filter`, so write them as `List.map` and `List.filter` with a `%!(Var x) =>`
lambda, which the pass already lowers because the receiving operation is a
bound native; `comptime-lowering.x`'s `map` case and the autodiff port's
`ad_unbind` both do this today, including calling another compile-time
function from inside the lambda. Take that route rather than teaching the
pass a calling convention for one caller.

## Capability before callers: the bootstrap had to carry the lowering

Established 2026-09-18, when Phase 5 first tried to put a `meta` function in
`lib/`. The checked-in `bootstrap/` had no `comptime.c` and no
`install_meta_function`, and `bin/x2c-bootstrap` - which `builds/stage.mk`
uses to translate every `src/*.x` and `lib/*.x` into `builds/0` - reported
`parse: missing closing parenthesis` on `meta static int f(int n)`. Nothing
in `lib/` or `src/` had needed it before, because the only `meta` functions
in the tree were in `lib/system-macros.xmacro`, which only
`unittest/test-system-macros.x` imports.

`make bootstrap-refresh && make build-safe` landed it as `e4db6c78`: ten
regenerated files plus `bootstrap/src/comptime.{c,h}` and
`bootstrap/lib/meta.{c,h}`. `make verify-fixtures` and `make verify` pass
against the refreshed chain. This is the intermediate validation `AGENTS.md`
asks for when a language transition is one the checked-in bootstrap cannot
consume, and it is a permanent coupling: every future bootstrap binary now
carries the comptime lowering, which is the second of Phase 7's two walls.

## Phase 6 - fold the AD port back (done)

Landed on `comptime-phase6-fold`. `comptime-autodiff.x` goes from 1181 to
1130 lines and from 111 to 106 compile-time functions;
`comptime-autodiff.stdout` is unchanged, which is the check that the
mathematics did not move. Gary has already decided the port stays a
demonstration, so `lib/autodiff.xmacro` is untouched and the two unported
paths - checkpointed loops and calls to an earlier differentiated sibling -
stay out of scope.

Eighteen recursive list builders are now `foreach` loops that push to an
`Array` and return it where a `List` is declared. Four more functions are
gone outright: `ad_sequence_from`, `ad_dispatch_from`,
`ad_call_partial_adjoints` and `ad_local_type_in` were folds or searches
their one caller now performs directly, and `ad_items_of` was dead. Every
`cdr` chain that read a fixed position is an index, and the five parts
`ad_loop_parts` answers are one destructuring declaration.

Three corrections to what this section said before the work.

- **`foreach` can nest, as of the Phase 6 integration.** The limitation Phase 6
reported was real and is now fixed: the declarator branch for a local with no
initializer never checked whether the enclosing loop had already allocated its
box, and a `foreach` output cell is declared without one, so a nested loop
always asked for a binding on the iteration path. It fills the box instead.
`ct_flatten` in `comptime-lowering.x` covers it. What follows is the finding
as Phase 6 recorded it, and the rewrites it drove are still worth keeping.

**`foreach` could not nest.** A `foreach` whose body holds another declines
  with "a value needing a binding is on a loop path", whatever the inner
  container is, because the inner loop's cells are values on the outer
  loop's iteration path. So a builder whose items expand to several
  statements cannot push them one at a time; it concatenates instead, and
  `ad_fwd_items`, `ad_sequence` and `ad_call_adjoint` read that way. The
  same decline covers a destructuring declaration inside a `foreach`, since
  the loop's output cell is read through a call.
- **One walk stays recursive.** `ad_declared_doubles` and
  `ad_declared_join` walk the whole tree, so concatenating once per node
  costs more than the recursion: as a loop the fixture translated in 1.41 s
  against 884 ms. They are a tree walk, not a list builder.
- **`ad_partial` as one `Map` costs 110 ms.** The table has to be built
  before it can be read, so a lookup evaluates all 27 derivatives where the
  chain evaluated one. Translation goes from 802 ms to 952 ms overall, of
  which about 42 ms is the `Map` itself, 110 ms its values, and 40 ms the
  loop idiom elsewhere. The alternative - a name-to-code `Map` and a
  27-label `switch` - is lazy but puts the primitive vocabulary in two
  places, which is the bloat this repository already names as a cause.
  The table was kept.

Of the 13 `$(def name (lambda (. rest) 0))` prototypes, five remain, each a
real cycle: `ad_tangent`, `ad_adjoint`, `ad_rev_item`, `ad_fwd_item` and
`ad_declared_join`. Seven were for names nothing called before their
definition, one was a duplicate, and `ad_is_loop_exit` was not in a cycle at
all, so its definition moved above its one caller instead.

### Original scope

Depends on Phases 1-3. Rewrite
`unittest/compiler-fixtures/comptime-autodiff.x` onto the constructs those
phases add: the eighteen recursive list builders become
loops over an `Array`, and `ad_partial` becomes a `Map`. Then decide, with
Gary, whether the result replaces `lib/autodiff.xmacro` or stays a
demonstration. Two paths are still unported and that decision needs them:
checkpointed loops (`$ad.checkpoint`) and calls to an earlier differentiated
sibling.

**The speed claim is now measured, and the question that blocked it is
answered.** `$ad.reverse` did not resolve in a standalone file because its
target was not `static`, and a public target "cannot gain new public
siblings" — `docs/src/reference/language.md` says so under the `Unit`
decorator rules, and every use in `unittest/test-autodiff.x` is `static` for
that reason. There is no defect here. The diagnostic is the weak part: a
public target reports `parse: expected syntax` at the decorator line without
naming the rule, which is what sent the earlier reading astray. Reproduced
without autodiff by splicing any Lisp-built function beside a public target.

Holding the derived function constant and varying only how many are derived,
on 2026-09-18:

| derivations | shipped `$ad.reverse` | ported `$c.gradient` |
| --- | --- | --- |
| 1 | 797 ms | 557 ms |
| 5 | 3.12 s | 873 ms |
| marginal, per derivation | 581 ms | 79 ms |

7.4x per derivation. The ported pass pays about 260 ms more to install its
111 compile-time functions and saves about 500 ms on every function it
differentiates, so it is ahead from the first one. The subject carries a
loop, a primitive call and a division, and both implementations return the
same gradient to nine decimals: `11.573550919 0.932986487`.

## Phase 7 - the builtin-macros bootstrap question (answered)

**`etc/builtin-macros.xlisp` stays Lisp.** Investigated 2026-09-18. The
mechanism to port it exists and was demonstrated; the ordering does not, and
buying the ordering costs more than the file is worth. Close this phase.

### What is actually in the file

Not the macro templating system. That is `src/macros.x`, in x2c. This file is
the Lisp body of three built-in macros declared in `etc/builtin-macros.xmacro`:
`foreach`, `$scope`, and `class`. Nothing else uses it, and it holds no name
table, so its lines are all work, unlike `etc/comptime.xlisp`.

| group | definitions | lines |
| --- | --- | --- |
| `x2c._foreach.*` | 16 | 173 |
| `x2c._scope.expand` | 1 | 14 |
| `x2c._class.*` | 35 | 316 |
| total | 52 | 503 |

By size: 34 definitions are five lines or fewer (103 lines) and are one
quasiquote apiece naming an AST shape, such as `x2c._class.ref` or
`x2c._foreach.assign`; 2 are six to nine lines; 16 are ten or more (387
lines) and carry the real logic. `x2c._class.defaults` alone is 80 lines.
The file calls 29 distinct compiler SDK natives and uses `apply` five times.

Usage of what it implements, across the 90 `.x` units in `lib/` and `src/`:
`foreach` at 684 sites in 51 units, `$scope` at 15 sites, `class` at 4.

### The established order

`_ensure_lisp` in `src/macros.x` creates the unit's Lisp session and
evaluates five libraries in order - `init`, `lisp-values`, `comptime`,
`compiler-sdk`, `builtin-macros` - and only then runs the `$lisp.bind` calls
that install the SDK natives. Every path that expands a macro or evaluates a
`$(...)` form calls `_ensure_lisp` first, including `_eval_template_form`,
which is the macro-replacement path. So `builtin-macros.xlisp` is live before
the unit's first expansion, always and by construction.

Three orderings were probed against `builds/0/x2c` rather than inferred.

- A `$comptime()` install is strictly file-position ordered. Calling the
  function above its decorator reports `(unbound (name probe_marker))`.
- An installed compile-time x2c function does drive a `Decorator` macro
  later in the same unit. A 17-line x2c port of `x2c._scope.expand`, wired to
  a local `$p7scope` macro, emitted exactly the `Scope_retain` / `defer
  Scope_release` shape the Lisp original does.
- A compile-time x2c function can reach a dotted SDK native during a real
  expansion: `$(def x2c_syntax_type x2c.syntax.type)` plus an x2c prototype
  made `x2c_syntax_type(place)` resolve and return `(int)` inside a decorator.

So the port mechanism works. What blocks it is where the install can happen.

### The circularity, and which part of it is real

Apparent: a compile-time x2c file does not need its own output to be
translated. Written without `foreach`, `class` or `$scope` - a constraint one
500-line file can meet - it parses and types like any other unit, and
`lower_comptime` reads the ordinary typed AST. There is no self-reference.

Real, in two places that the phase brief did not name.

- **Ordering.** An install is driven by a decorator the parser reaches in
  source order, so it can only serve expansions after it, in the same unit.
  To serve `foreach` in every unit the compiler would have to translate a
  shipped compile-time x2c file itself, at session start. It cannot do that
  during the library load as `_ensure_lisp` is written, because
  `x2c.comptime.install` is not bound until after the five libraries are
  evaluated. Reordering that, plus a sub-translation entry point, is new
  machinery whose only caller would be this port.
- **The bootstrap chain.** The checked-in `bin/x2c` has no
  `etc/comptime.xlisp` and no comptime install at all; run against the
  probe it reports `(unbound (name x2c.comptime.install))`. It is the binary
  `make build-safe` uses to translate `src/` and `lib/`, which contain those
  684 `foreach` sites. Moving `foreach` out of Lisp breaks the chain until a
  bootstrap refresh lands the capability first, and thereafter every
  bootstrap binary must carry comptime lowering to compile the runtime at
  all. That is a permanent coupling, not a one-time transition.

`protect_x2c` in `lib/lisp.x` is a third, smaller wall: once the first
`x2c.*` native is bound, no source can `def` an `x2c.`-prefixed name, so the
alias that would point `x2c._foreach.expand` at a ported function has to be
evaluated inside the privileged library load. Probed: `$(def
x2c._scope.expand 1)` in a unit reports `bad-state`.

### The cost, measured

Installs are not free and the cost would be per unit. Translating the 1085
definition lines of `comptime-autodiff.x` takes 451 ms with its 111
`$comptime()` decorators and 293 ms with them stripped, against 62 ms for a
trivial unit: 158 ms of install for 111 functions, on top of 231 ms of parse
and type. A ported `builtin-macros` of 52 functions and about 500 lines would
add roughly 180 ms to any unit that expands a macro. `src/*.x` is 34 units in
8.75 s today, so that is about +70% on the compiler's own translation.

A process-level cache of the lowered forms would amortize the parse, type and
lower across the units in one `x2c` invocation, leaving only the per-session
`eval`. That is the one mitigation worth knowing about, and it is another
mechanism with one caller.

### What could still be ported, if anything

Nothing, as things stand. All 52 definitions serve compiler-shipped macros
that must be live before the unit's first expansion, and none of them is a
helper that merely happens to live here.

The only boundary with a real argument behind it is `class`: 35 definitions
and 316 lines, used at 4 sites in `lib/` and `src/`, and never needed by a
unit that does not write `class`. It could in principle be installed lazily,
the first time the `class` keyword is seen. That still needs the reordered
`_ensure_lisp`, the sub-translation entry point, 29 SDK aliases with x2c
prototypes, and `apply` rewritten as literal templates at its five sites -
and it pays about 100 ms in every unit that uses `class`. The recommendation
is no: the machinery does not earn 316 lines.

Reopen this only if a shipped compile-time x2c unit becomes necessary for
another reason. Then `class` is the first thing to move, `$scope` the second,
and `foreach` last or never.

## etc/init.xlisp, measured 2026-09-18

Earlier revisions called all 248 lines permanent substrate. That was wrong.
The file holds 3 native aliases, 7 `defmacro` and 36 `defun`, so the bulk is
ordinary functions.

- **About 20 of the 36 `defun`s port today**: `caar`, `cadr`, `cddr`, `last`,
  `length`, `str`, `repr`, `substring` and the rest that take no function.
- **The rest needed M7, which is built.** The first five are `map`, `filter`,
  `foldl`, `member` and `assoc`; three take a function, and those three are
  written as meta functions in `comptime-lowering.x` and answer correctly.
  What they still need is somewhere to be installed, which is M8.
- **The 7 `defmacro`s are a different mechanism.** A Lisp `defmacro` expands
  when the evaluator meets a form; an x2c `macro` expands x2c source at parse
  time. They are not two spellings of one thing. They exist to serve
  hand-written Lisp, so they shrink as it shrinks rather than porting in place.
- **No circularity** for the functions. A meta function whose body reaches only
  the core lowers to `car`/`cdr`/`cond`, so `map` as a meta function is not
  self-referential. The core in the objective above is the real floor.

All of it needs M8, because these are session-start definitions with no
importing unit.

## The loop parameter ceiling, and the narrowing that followed

**A loop now carries only the locals it names** (`_lower_referenced` in
`src/comptime.x`). The investigation below established that the constant was
a symptom and `_lower_loop` was the lever: it built its parameter list from
every entry of the environment, so a local nine deep anywhere in the function
pushed the loop past `LISP_AUTO_PARAM_MAX` and onto the evaluator, whether or
not the loop ever read it.

The set is the locals named in the test, body, step and the rest of the block,
plus those an enclosing loop's continuation asks for, plus those the body
declares in a cell. A local left out is one that is never read; leaving one
out wrongly declines as an unbound local rather than answering wrongly.

Measured on a loop with twenty dead locals in scope: **135 ms before, 79 ms
after.** On `comptime-autodiff.x` it does not move - about 995 ms either way,
the same result raising the constant gave - because that corpus has no
function whose loop is crowded by locals it does not use. The value is that
the cliff is gone rather than moved, which matters to anyone writing a meta
function by hand. `ct_live_set` in `comptime-lowering.x` pins the correctness.

### The original investigation (investigated 2026-09-18, no change)

**Do not raise `LISP_AUTO_PARAM_MAX`.** The cliff M4 found is real and the
constant is only where it surfaces. `_lower_loop` passes the enclosing
function's whole lexical environment, so the cliff tracks how many locals a
compile-time function declares, not what its loop uses. Raising the bound
moves that cliff without removing it, buys nothing measurable on the
repository's own corpus, and costs 6% of the compile-time recursion ceiling.
Measured on branch `comptime-loop-params` off `0469ee39`.

### What the limit costs

A probe with a dialable live set - K accumulators plus a counter and the
parameter, looping 3000 times at compile time - puts the step exactly at the
ninth parameter. Translate time, best of three:

| live locals | cap 8 | cap 32 |
|---|---|---|
| 6 | 80 ms | 83 ms |
| 7 | 82 ms | 83 ms |
| 8 | 84 ms | 118 ms |
| 9 | **1.64 s** | 94 ms |
| 10 | 1.74 s | 126 ms |
| 11 | 1.86 s | 118 ms |
| 12 | 1.99 s | 97 ms |

One more live local costs 20x. Every iteration of the loop runs through the
evaluator instead of the machine.

### Why the limit is 8

It is a buffer someone sized, not an encoding. `Var argv[LISP_AUTO_PARAM_MAX]`
in `_auto_apply` is the only thing the constant sizes. An activation record
borrows that array - `_machine_env_set` stores `const Var *values` and a
count - so a parameter costs nothing per frame. The argument count rides in
`MachineWord.b`, an `unsigned char` that `MachineBuilder.emit` range-checks
into `[0, 255]`, so the encoding permits 255. `MACHINE_CODE_MAX` is not
involved; M4 measured the largest program at 511 words of 4096.

Two other sites read the constant. `_auto_compile_call` bounds the arguments
a compiled call may pass, which is how a lowered loop's own call site
declines alongside the loop. `_auto_compile_qq` reserves it as quasiquote
headroom against `MACHINE_VALUE_MAX`, 248 slots at 8 and 224 at 32. At run
time `LispMachine._call` bounds `argc` against `MACHINE_LOCAL_MAX` of 256 and
crosses to the evaluator when there is no room, so a wide call degrades
rather than failing.

### What raising it would cost

Raising to 32 adds 192 bytes to `_auto_apply`'s C stack frame. Measured by
bisecting the depth of a non-tail compile-time recursion that still builds:
12900 at cap 8, 12100 at cap 32, a 6% reduction. Both ceilings end in a
segmentation fault rather than a diagnostic, which is a separate defect and
is not caused by the constant.

On the corpus the raise does what it claims and nothing more. The 8 declines
`comptime-autodiff.x` produces become 6 - 895 analyses, 887 frozen at cap 8
and 889 at cap 32, with the six remaining declines all rest-parameter
lambdas from the Lisp standard library. Translate time does not move: seven
runs each give a median of 987 ms at cap 8 and 973 ms at cap 32, inside the
benchmark noise floor. The two loops it frees, `loop56-ad_call_tangent` and
`loop244-ad_call_adjoint`, iterate over a call's arguments a few times each,
so the evaluator was never doing much work in them.

Answers are unaffected either way: the probe's compile-time result is
byte-identical at both caps across the whole dial, K = 4 through 12.

### Why the lowering is the lever

`_lower_loop` builds its parameter list from every entry of `l.env`, the
lowering environment at the loop's position, rather than from the locals the
loop reads or writes. A loop over three variables is therefore made
ineligible by unrelated declarations elsewhere in the same function. Probed
at cap 32 with a loop touching exactly three locals and U further locals in
scope but never named inside it:

| locals in scope | translate |
|---|---|
| 31 | 96 ms |
| 32 | 104 ms |
| 33 | **1.17 s** |
| 43 | 1.32 s |

The cliff follows the count of declarations, not the loop. Passing the
loop's live-in set, or one environment value for the remainder, removes the
coupling; raising the constant only relabels it. That work belongs with
whoever next touches `_lower_loop` and is not worth doing on its own, since
the corpus shows no time to recover.

### What would reopen this

A compile-time function whose loop both carries a wide live set and iterates
enough for the evaluator cost to show. Nothing in the repository does today.
If one appears, narrow `_lower_loop`'s parameter list first and measure
again before touching the constant.

One note for whoever does: `lisp_auto_declined_form_releases_programs` in
`unittest/test-lisp-auto.x` uses a nine-argument call as its example of a
form that declines, so it fails at any larger bound. Widening its two calls
past the new bound restores it. A declining argument does not substitute -
`_auto_compile` rewinds it to an interpreted word and the enclosing call
still compiles.

## Handoff

The branch is self-contained. Verified on 2026-09-18 by forking `d553a2f3`
into a clean worktree with nothing from `.context/`: `make build-safe`
succeeded, `make verify-fixtures` passed 719 fixtures, and
`comptime-autodiff` derived its five siblings in 753 ms with every derivative
matching. A fork needs no files that this branch does not carry.

`x2c-lowers-to-lisp` has no upstream. A local worktree off this repository
works as is; anything off this machine needs the branch pushed first.

Give each agent one phase. Phase 1 goes first because 5 and 6 depend on it.
Phases 2, 3 and 4 can run beside it and beside each other; 5 and 6 wait.
Phase 7 is answered and needs no agent. Each agent gets the same brief:

> You are working on branch `x2c-lowers-to-lisp` in the x2c repository. Read
> `AGENTS.md`, then `plans/comptime-x2c-generalization.md`, then
> `plans/x2c-lowers-to-lisp.md` for the design record. Implement **Phase N**
> and only Phase N.
>
> The pass is `src/comptime.x` and its runtime is `etc/comptime.xlisp`. A
> `Unit` decorator captures the pre-transform AST, so design against
> `--dump-ast` from a decorator, never against `--dump-transforms`.
>
> Your evidence goes in `unittest/compiler-fixtures/comptime-lowering.x`: add
> one `$comptime()` function per construct you land, call it from `main` in
> expression position, and regenerate `comptime-lowering.stdout` by running
> the built program. Run `make verify-fixtures` before you finish. Never run
> `make verify-fixtures-update` to make a failure go away; it rewrites the
> expectations you are supposed to be checking.
>
> Work on a branch off `x2c-lowers-to-lisp` and merge back into it. Nothing
> reaches `main`; Gary has not given that green light. Do not edit a function
> another phase owns without saying so.
>
> Report what you landed, what you verified, and anything you declined and
> why.

Two traps have already cost time on this branch and are worth repeating to
whoever takes Phases 1 and 2. `*` is a sequence binder in a match pattern, so
`%(op * ?operand)` matches every `op` form; match a unary operator by arity
and then compare the operator symbol. And a decline is always better than a
silent wrong answer: both defects found here — a pattern that never fired and
a discarded operand whose call never ran — produced plausible output rather
than an error.

## The decision that gates a reserved word (decided)

**Decided 2026-09-18: the word is `meta`, contextual, and both forms are
emitted.** See `plans/meta-functions.md`. The analysis below stands except
for one claim it rests on: a compile-time function does *not* omit its
runtime form, and never did.


Not scheduled, and deliberately left until Phases 2-4 land. Recorded here
because it is the thing most likely to be discovered late.

`$comptime()` is a `Decorator` macro today. It reads as a transformation, but
a compile-time function is not transformed: it is a function whose lifetime is
translation rather than run time, which is the kind of fact `static` and
`inline` state. Three costs follow from the spelling, each measured rather
than asserted:

- `comptime-autodiff.x` carries 13 `$(def name (lambda (. rest) 0))` lines,
  which are C prototypes written in Lisp. A decorator fires per definition and
  cannot see a forward declaration.
- A `Unit` decorator captures the pre-transform AST, so the pass re-derives
  conversions the compiler already knows how to insert. `_lower_coerce` exists
  only for that, and before it existed the gap was a silently wrong container
  and a segfault.
- A public decorator target cannot gain new public siblings, which is why
  `$ad.reverse` needs a `static` target. A keyword would not inherit that rule.
- Phase 7 adds a fourth: an install is driven by a decorator the parser reaches
  in source order, which is what makes a session-start install inexpressible.

Two of those are really about **where in the pipeline the pass runs**, not how
it is spelled. That decision is now settled: `plans/meta-functions.md` M3
scouted moving the lowering after the transform and declined it, because the
transform erases a lambda's body into a generated sibling and an interpolated
string into raw C text, both of which the pass lowers today. `_lower_coerce`
and the pre-transform re-derivation stay. The `meta` marker that M1 landed
therefore buys better prototypes and better diagnostics, which is what the
remaining option was worth.

Against a keyword: x2c is shipped, so the identifier breaks callers, and every
reserved word spends from a closed vocabulary that has been a recurring source
of bloat. Both argue for doing it once, as part of the larger rework, rather
than ahead of it.

## Validation

Focused per phase: `make build`, that phase's fixture entries, and the whole
`comptime-lowering` fixture, which `./unittest/compiler-fixtures/run.sh
check` runs on its own. The unit suites (`make -C unittest test-all` then
`./unittest/test-all`, 915 tests, of which `lisp_suite` is 56) have caught
nothing in this work so far but are cheap and stay. There is no
`test-lisp` target; an earlier revision of this section named one.

Branch merges back to `x2c-lowers-to-lisp` need no gate. Delivery to `main`
is a separate decision that Gary owns and has not given.

## Plan review

**Facts the producers establish.** The typed AST already carries the
receiver's type on every `expr` node, so Phase 1's `getindex` dispatch reads
a fact the type pass established rather than inferring one. `_lower_loop`
already constructs both the self call and the leave continuation, so Phase 2
consumes values that exist rather than recomputing control flow. Neither
phase rechecks those facts.

**Deletion and reuse.** Phase 1 deletes the `arrays` decline and the
`array`/`map`/`composite`/`commas`/`getindex`/`index` entries in the scan's
reject list rather than adding a parallel path, and reuses the cell machinery for
local arrays instead of introducing a second mutable representation. Phase 2
deletes three reject entries and adds one function, `_lower_switch`. Phase 6
deletes eighteen hand-rolled list builders and a twenty-seven-branch chain
from the port. The only lasting new mechanism in the whole plan is the
loop-continuation state Phase 2 carries, which exists because `break` has no
other way to name the loop's exit.

**Why this is idiomatic x2c.** The pass is a `match` over the canonical AST
that produces Lisp forms through literal templates, which is how the rest of
`src/` reads. Phase 1 makes the ported code use `Array` and `Map` the way
`src/` does, instead of the cons-recursion the missing constructs force
today. Nothing here imports a framework; the exit-code machinery that a
general `switch` or a non-local `break` would need is explicitly refused in
favour of a decline.

**Validators, diagnostics, and negative fixtures.** Three deliberate
declines carry dedicated wording: fallthrough in a `switch`, `defer` in a
compile-time function, and `goto`. Each protects a real wrong answer rather
than failing earlier — silently accepting fallthrough would run the wrong
arms, and silently accepting `defer` would free a value the evaluator owns.
The `comptime-declines` fixture exists to check that wording, and is the only
negative fixture the plan adds. Phase 4 adds no validator; it either removes
a decline or records why the decline stays.
