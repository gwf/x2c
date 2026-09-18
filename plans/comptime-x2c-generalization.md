# Comptime x2c generalization

> Status: active
>
> Scoped 2026-09-18 on branch `x2c-lowers-to-lisp` after the autodiff port
> landed. Phases 0 and 1 are done and merged; Phases 2-4 are the rest of the
> pass, 5-7 are ports and one investigation. Nothing on this branch reaches `main` without Gary's
> explicit green light. The design in `plans/x2c-lowers-to-lisp.md` is
> settled and this plan does not revisit it.

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
| `etc/builtin-macros.xlisp` | 504 | Phase 7 investigates; bootstrap question |
| `lib/var-tags.xmacro` | 295 | Phase 5 |
| `etc/init.xlisp` | 237 | substrate, stays |
| `etc/comptime.xlisp` | 121 | name table, stays |
| `etc/lisp-bindings.xlisp` | 119 | name table, stays |
| `etc/lisp-values.xlisp` | 97 | name table, stays |
| `etc/compiler-sdk.xlisp` | 43 | Phase 5 decides |
| `etc/lisp-extras.xlisp` | 34 | Phase 5 decides |
| `lib/error-macros.xmacro` | 32 | Phase 5 |
| `lib/error-private.xmacro` | 20 | Phase 5 |
| `lib/system-macros.xmacro` | 8 | Phase 5 |
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
general case.

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

## Phase 2 - control flow

Owns `_lower_stmnt`, `_lower_loop`, and a new `_lower_switch`.

- `break` and `continue` need no exit codes. `_lower_loop` already holds both
  the self call `(again ...)` and the inlined `leave` continuation; carry
  them in the `Lowering` state the way `on_loop` is carried, and lower
  `continue` to the first and `break` to the second. A `break` or `continue`
  outside a loop declines.
- `do`/`while` rewrites to a `while` with a first-iteration flag, which is
  what `ad._rev-do` in `lib/autodiff.xmacro` already does for its subject
  programs. Mechanical.
- `switch` lowers to a `cond` chain over a subject bound once. Fallthrough is
  deliberately not supported: an arm that does not end in `break` or `return`
  declines with a reason naming fallthrough. The repository writes `switch`
  this way already, and a fallthrough state machine would be machinery with
  no caller.
- `goto` and labels decline permanently. Record that as a decision, not an
  omission.

## Phase 3 - the mechanical gaps

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

## Phase 4 - typed captures in patterns

Owns `_lower_arms` and whatever in `src/literals.x` the investigation finds.

A `case %(call ?(String n))` pattern does not fold to a constant: folding
leaves an `expr` node carrying a run-time conversion, so the arm was
previously matched against raw AST and silently never fired. The pass now
declines it with "case pattern is not folded", which is correct but blocks a
pattern the compiler itself uses constantly.

Start with an investigation: establish whether a typed capture in a pattern
can fold to the capture atom at literal-folding time, since the type is only
there to type the binder at the use site. If it can, the fix is in folding
and the decline disappears. If it cannot, record why and keep the decline.
Do not build a second folding path in the pass.

## Phase 5 - port the remaining macro Lisp

Depends on Phases 1-3. `lib/var-tags.xmacro` at 295 Lisp lines is the real
one; the error and system macros are small. `etc/compiler-sdk.xlisp` and
`etc/lisp-extras.xlisp` are judged during this phase: some of their contents
are name tables and stay.

Each port keeps the macro's public surface identical and is verified by the
suites that already cover it, not by new tests written for the port.

## Phase 6 - fold the AD port back

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

## Phase 7 - the builtin-macros bootstrap question

Independent of the others and investigation-first.
`etc/builtin-macros.xlisp` is 504 lines and is the macro templating system
that `$comptime` itself runs on. Its definitions must be live before any user
macro expands, whereas comptime x2c functions install per unit. Establish
whether a compile-time function can be installed early enough to serve the
macro expander, and what would have to hold for that to be safe. The answer
may be that this file stays Lisp; that is an acceptable outcome and should be
recorded rather than worked around.

## Handoff

The branch is self-contained. Verified on 2026-09-18 by forking `d553a2f3`
into a clean worktree with nothing from `.context/`: `make build-safe`
succeeded, `make verify-fixtures` passed 719 fixtures, and
`comptime-autodiff` derived its five siblings in 753 ms with every derivative
matching. A fork needs no files that this branch does not carry.

`x2c-lowers-to-lisp` has no upstream. A local worktree off this repository
works as is; anything off this machine needs the branch pushed first.

Give each agent one phase. Phase 1 goes first because 5 and 6 depend on it.
Phases 2, 3 and 4 can run beside it and beside each other; 5, 6 and 7 wait,
except that 7 is investigation and can start any time. Each agent gets the
same brief:

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

## Validation

Focused per phase: `make build`, that phase's fixture entries, and the whole
`comptime-lowering` fixture. The Lisp suite (`make -C unittest test-lisp`,
915 tests) has caught nothing in this work so far but is cheap and stays.

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
