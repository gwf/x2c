# Meta functions

> Status: active
>
> Scoped 2026-09-18 on branch `x2c-lowers-to-lisp`, after Phases 0-4, 6 and 7
> of `plans/comptime-x2c-generalization.md` landed and Phase 5 blocked on the
> capability this plan supplies. The word and the three-lifetime design are
> Gary's decisions, taken 2026-09-18. Nothing reaches `main` without his
> explicit green light.

## The result

`meta` marks a function the compiler may run as well as emit. One body, three
lifetimes:

1. **Compile time.** Lowered to Lisp, word-compiled, used during translation,
   discarded at the end of the unit.
2. **Run time.** Emitted as an ordinary native function, like any other.
3. **Later.** Its word-compiled form preserved in the artifact, so an
   interpreted x2c runtime can call it without recompiling, and a call whose
   arguments are all constants can be folded at the call site.

The word names the function's role rather than a phase, which is why it is
`meta` and not `comptime` or `consteval`. A phase-naming word becomes false
the moment the same body serves more than one phase.

## What already works, and the claim it corrects

`$comptime()` already emits the runtime function. `_sdk_comptime_install`
returns `%($fn)`, so the decorator splices the original definition back into
the unit. Verified 2026-09-18: one `$meta()`-decorated `poly` answered a
compile-time call, a run-time call, and a non-constant run-time call with the
same value.

Earlier drafts of `plans/comptime-x2c-generalization.md` asserted that a
compile-time function emits no C, and reasoned from it. That was never true
and nothing was built on it beyond the wording, which this plan supersedes.

Two consequences. `consteval` and every other "compile-time only" spelling
would name behaviour this system does not have. And the Phase 5 blocker is
smaller than recorded: the macro-import loop does not need a way to accept a
definition and emit nothing, it needs to accept a definition and emit it the
way a header already does.

## The word

`meta` precedes the declaration, where `static` and `inline` go:

```x2c
meta List ad_unbind(Var form) { ... }
meta static int width(String text) { ... }
```

It is **contextual**. `meta` starts a meta declaration only when what follows
parses as a function declaration or definition; everywhere else it is an
ordinary identifier, so `List meta = ...` in `examples/magic/ways-to-agree.x`
keeps working. This is the same treatment `keyword` already gets, with one
difference that matters: `keyword` resolves through the macro machinery, and
`meta` must resolve in the parser, because the parser has to know before
macro expansion runs.

`meta` composes with a storage class rather than replacing one. Both forms are
emitted, so `static` still says what it always said about the runtime form.

There is no opt-out spelling. A meta function whose runtime form cannot be
emitted has no caller today, and inventing `meta only` before one exists would
be machinery without a user.

## M1 - the parser marker (done)

`Compiler.meta_form_is_definition` in `src/parse.x` recognises the word, and
`Compiler.install_meta_function` in `src/macros.x` runs the install the
decorator's SDK native runs. `comptime-lowering.x` prints `mt_poly` and
`ct_poly` at compile time and at run time, four equal answers, and
`comptime-declines-meta` pins the refusal.

Three facts the work established.

- **The contextual test needs both halves.** `test_declaration()` at the
  token after `meta` rejects `meta f(int);` where `meta` is a typedef name,
  and a scan for a declarator ending in a parameter group rejects
  `meta int x = 3;`. Either test alone accepts something the other refuses.
- **The macro session is lazy.** `_ensure_lisp` runs on a Lisp form, an
  import, or a macro expansion, so the decorator always had a session by the
  time its native ran. A marker in the parser has none, and
  `install_comptime` aborted on a null `macro_lisp`. The install therefore
  belongs beside `_ensure_lisp` in `src/macros.x`, doing what
  `_eval_template_form` does before it: run pending declaration effects,
  then ensure the session.
- **Collection has to skip the word too.** `_shallow_finish_declaration`
  reads the runtime declaration; without the skip it takes `meta` for the
  type.

One diagnostic beyond the shared refusal: `meta` on a prototype reports that
a meta function needs a body, because there is nothing to install and a
silent acceptance would look like the compile-time form existed.

The decorator stays working; `meta` is a second spelling for the same effect
until M4, not a replacement. The book gains nothing here because it does not
document compile-time x2c functions at all yet.

## M2 - the import loop

`src/macros.x:1121` accepts a keyword definition, a macro definition, or a
top-level `$(...)` form, and reports `unexpected form in macro import` for
anything else. Add a branch for a `meta` declaration.

The importer is already a `Compiler.new_shared(c)` holding the caller's `sym`,
`fn_defs`, `macros` and `macro_lisp` with `borrowed_lisp = 1`, so the install
lands in the consuming unit's session with no new plumbing. What the branch
decides is emission, and it is the ordinary header problem: a `meta static`
definition in an import emits one copy per consuming unit, which is what
`lib/*.xmacro` macros already do; a non-`static` one needs the declaration and
definition split that public macro families already use.

This unblocks `plans/comptime-x2c-generalization.md` Phase 5 and reopens its
Phase 7 verdict. Do not re-scope either until this lands.

## M3 - the pipeline position

**Do not build this.** Scouted 2026-09-18 on branch `meta-m3-pipeline` with a
throwaway probe that ran `Compiler.transform` on one function at its install
point and dumped the result. The ordering the milestone worried about is
satisfiable. The premise underneath it is not: the transformed tree cannot
carry a compile-time function, because the transform erases two constructs
the pass already lowers.

The milestone's reasoning, kept because the defects it names were real:
`_lower_coerce` re-derives conversions the compiler knows how to insert -
`Array_list` at a `List` declaration, `List_array` at an `Array` one,
`Symbol_str` at a `String` return - and each was a silent wrong answer
before it was found.

### The ordering is satisfiable, and it is not the blocker

`Compiler.install_meta_function` runs from `Compiler.parse_top_level`, so a
`meta` function is installed the moment its definition parses, and a macro
defined later in the same unit calls it during expansion. Probed: a
`meta int mt_len(List node)` above a `macro Expression $nodelen(Expr $e)`
folds `$nodelen(1 + 2)` to `printf("%d\n", 3)`. `Compiler.transform` runs in
`_compile_file` after `unit.parse()` returns, which is after all expansion.
The two pass positions are therefore strictly ordered install-then-transform
and no reordering of the passes serves both.

What does work is calling `Compiler.transform` on the one function at the
install point, out of its pipeline position. It returns exactly the tree
`--dump-transforms` prints, mid-parse, and re-transforming it at the unit
level is idempotent: a `meta` function whose transformed nodes are returned
to `parse_top_level` produces byte-identical C, except that the lambda
sibling the transform generated lands beside the function instead of at the
end of the unit. The cost is one extra transform per compile-time function:
`comptime-autodiff.x` translates in 0.99 s today and 1.04 s with the extra
pass over its 106 functions, five runs each, +5.4% or about 0.5 ms a
function.

### The transform erases two constructs the pass lowers

- **A lambda has no body left.** `items.map(%!(Var part) => ...)` becomes
  `List_map(items, _x2c_func_handle_0)`, where the handle is a file-scope
  `static Func` assigned `Func_new(_x2c_func_adapt_0, ...)` at program
  startup and the body is a separate static `_x2c_lambda_0` reached through
  an `x2c_func_value_argument` adapter. The AST at the call site holds a
  reference to a run-time value. Lowering it means mapping a handle binding
  back to a generated sibling - by shared name suffix, since the AST does not
  record the association - and rebuilding the lambda the transform took
  apart.
- **An interpolated string is raw C text.** `%"$stem-${n}"` becomes
  `(expr ("String") ("String_join(NULL, " (expr ("List") (cons ...)) ")"))`.
  The head of the content list is emitted C, not an operation to look up, so
  lowering it needs a table mapping C text back to compile-time bindings.

Both are in the ledger the milestone must not move: `ct_doubled` and
`ct_label` in `comptime-lowering.x`, `ad_unbind` and `ad_local` in
`comptime-autodiff.x`.

Reading the transformed tree for literals and indexing and the pre-transform
tree for lambdas and interpolation is two representations of one body, which
is the thing this milestone existed to remove.

### The decorator cannot carry a transformed tree at all

`_sdk_comptime_install` returns `%($fn)` and the `$comptime()` decorator
splices it back into the unit, where a decorator's replacement is re-bound.
A transformed function is not bindable syntax: returning one reported
`parse: expected syntax` at every `$comptime()` site in
`comptime-lowering.x`. The decorator spelling, which this plan keeps through
M3, would therefore need the transform run on a discarded copy - which also
advances the lambda, adapter and literal-cache counters, so `_x2c_lambda_0`
becomes `_x2c_lambda_1` and the whole constant table renumbers.

### What the transformed tree would have given

The half that does lower is real and worth recording, because it is what a
future design would aim at. `[1, 2, 3]` at a `List` declaration becomes
`Array_list(varray(int_var(1), ...))`, `{}` at a `Map` one becomes `(vmap)`,
`xs[0]` becomes `List_getindex`, `m[<k>]` becomes `Map_getindex` around
`Symbol_var`, and `match` becomes `matchcases` with a `Var_list` subject and
per-binder `Var_string` conversions. Most of those names are bound in
`etc/comptime.xlisp` already; `Symbol_var` and `Var_string` are not, so the
transformed tree introduces callees the pass declines on today and the
dictionary grows to meet it.

Against that, the deletion is `_lower_coerce` at 17 lines plus the literal
and index productions, and the additions are a handle-to-sibling association,
a C-text table, and the missing bindings. It adds more machinery than it
removes.

### Consequence

`_lower_coerce` stays, and the three pairs it covers stay named there:
`Array` to `List`, `List` to `Array`, and `Symbol` to `String`. They are the
only pairs a Lisp value can tell apart, so the list is closed; extend it only
when a new destination type needs one, and write the fixture in
`comptime-lowering.x` that shows the conversion arriving.

M4 is already declined, so nothing waits on which tree M3 would have
selected.

## M4 - serialize the word-compiled form

**Do not build this.** Scouted 2026-09-18 on branch `meta-m4-scout` with a
throwaway probe in `lib/lisp.x` that dumped every frozen program the compiler
produced while translating `unittest/compiler-fixtures/comptime-autodiff.x`,
whose 106 `$comptime()` functions are the largest compile-time x2c corpus in
the repository. The qualifying fraction is high, but the two premises this
milestone rests on are both wrong: word compilation is not the cost, and the
constant table is not a value table.

### What the measurement found

**Qualification is not the problem.** 102 of the 106 compile-time functions
froze a program, and none of the 102 was rejected. The other four -
`ad_assign`, `ad_call_adjoint`, `ad_fwd_update`, `ad_step` - never reached
`_auto_apply`'s two-call threshold, so they were never analysed at all.
Across the whole translation 887 of 895 analyses froze. The 8 declines were
six rest-parameter lambdas from the Lisp standard library (`and`, `or`,
`list`, `append`, `string-append`, `begin`) and two lowered loop helpers,
`loop56-ad_call_tangent` and `loop244-ad_call_adjoint`, with 11 and 12
parameters against `LISP_AUTO_PARAM_MAX` of 8. That second pair is worth
keeping: a lowered loop takes one parameter per live variable, so a loop body
with nine or more of them falls off the machine and runs its every iteration
through the evaluator. `MACHINE_CODE_MAX` never came close to binding - the
largest program was 511 words of 4096, the median 14.

**The saving is 0.7%.** Word-compiling all 698 top-level programs costs
6.8 ms of a 970 ms translation (five runs each: 6.5-7.1 ms against
0.93-0.98 s). That 6.8 ms is the entire quantity M4 can remove, and it is
below the noise floor of the benchmark lanes that would have to show it.

**The constant table holds live process addresses.** Of the 6401 constants
in the translation, 995 (15.5%) contain a `<func>` or `<lambda>` pointer
transitively; of the 1808 belonging to the 106 functions, 387 (21.4%) do.
Every single `MW_LEXPAND` constant does - all 798 of them - because
`_auto_compile_special` stores `%($form (($head $expected)))` with
`$expected` the address of the special-form `Func`, and `_auto_bindings_ok`
compares it by raw `u64`. All 197 `MW_LLAMBDA` constants are live `Lambda`
records, and `Lisp.immediate` dereferences their `params` and `body`.

**More than half the table is the source program.** Classified by the opcode
that names them, the 1808 constants of the 106 functions are 763
`MW_LPRECALL` raw argument lists, 336 `MW_LEXPAND` guard sites, 1 `MW_LEVAL`
form, 359 `MW_LGLOBAL` names, 291 `MW_LCONST` literals, 51 `MW_LLAMBDA`
children and 7 shared between `MW_LPRECALL` and `MW_LCONST`. The first three
- 1100 of 1808, 61% - are quoted sub-forms of the body. Rebuilding them at
load is not cheaper than re-evaluating the `def` and word-compiling again,
which is what the 6.8 ms already buys. No `MW_LCAPTURE` constant appeared at
all: lowered compile-time functions have no closures.

### The serializable shape, confirmed

The code section is position-independent and pointer-free, as the plan
assumed. `MachineWord` is four `unsigned char` and two `short`;
`MachineBuilder.emit` range-checks `a` and `target` into
`[-1, MACHINE_CODE_MAX)` and every other field into a byte. `root` is the
entry pc and is always 0 for a Lisp program, which `_auto_analyze` sets
directly; `length` is the code word count; `const_count` and `binder_count`
size the two tables packed after the code in the same allocation. The 102
programs are 4921 code words and 1808 constant slots, 55 KB in total.

`binder_count` is always 0. Binders are a `Match` mechanism -
`MachineBuilder.binder` is called only from `lib/match.x` - and all 887
frozen Lisp programs carried none. The plan's "emit their spellings and
re-intern on load" bullet describes work that does not exist.

### The literal-fold path cannot rebuild the constants

`Compiler.cache_literal_list` states what it takes: "`values` may contain
nested `List`s, `String`s, and `Symbol`s." `_cache_literal_var` has exactly
those three branches, and `Compiler.id_keys` holds exactly three key shapes,
`(string ...)`, `(var ...)` and `(cons ...)`. Measured against that path, 538
of the 106 functions' 1808 constants are expressible (29.8%), and **no
function has a wholly expressible constant table** - 0 of 102. Three kinds
are missing, counted as leaf occurrences within those 1808 constants:

- **`Atom`**, tagged `<lsym>`; 930 occurrences, and 3783 across the whole
  translation, the most common leaf in the corpus. It is every Lisp name in
  every quoted form. An `Atom` falls into `_cache_literal_var`'s Symbol
  branch, where `Var.symbol` returns 0 for it, so the spelling is lost
  silently. It is re-internable by spelling, so this is a real but small gap:
  one cache-key kind.
- **integers**, tagged `<i32>`; 191 occurrences, 716 across the translation.
  Same branch, same silent loss, also one small cache-key kind.
- **`<func>` and `<lambda>`**; 336 and 53 occurrences, 798 and 318 across the
  translation. These are not values. A `func` is the address the session held
  for a special form at lowering time and exists only to be compared against a
  fresh lookup; a `lambda` is a child record with its own `params`, `body`,
  `captures` and `auto_program`. Neither has a spelling to re-intern, so no
  cache-key kind reaches them.

The `func` case is not merely mechanical. Storing the name and re-resolving it
on load would change what the guard means, from "this binding is the same
object as at lowering" to "this binding is whatever it is now", which silently
accepts a redefinition that happened before the artifact loaded. The `lambda`
case is circular: serializing an `MW_LLAMBDA` constant means serializing the
child's body, which is the recompilation the milestone exists to avoid.

### The program is not self-contained anyway

`MW_LGLOBAL` loads a callee by name and `LispMachine._call` then asks
`Lisp.program(callable)` for its program. A deserialized program therefore
still needs the `Lambda` record - and so the `def`, and so the lowered body -
both for itself and for every compile-time function it calls, or each call
crosses back to the evaluator. Installing a word-compiled form without its
Lisp body has no meaning in the current design.

### What to measure, if this is revisited

The quantity is load-to-first-call: from `Lisp` session open to the return of
the first machine-executed call of one meta function. The instrument already
exists - `LispAutoStats.analyses` plus a monotonic clock around
`_auto_analyze` behind an environment variable, which is exactly the probe
this scouting run used and discarded - and `Lisp.auto_disable`, which
`unittest/test-lisp-auto.x` already drives, is the control arm.

The baseline is recorded above: 6.8 ms for 698 programs, about 10 us each,
against a 970 ms translation. Anything proposed here has to beat that, and
the honest target is not the wordcode. If a later runtime should call a meta
function without recompiling, the thing worth persisting is the **lowered
Lisp forms**, which `$(x2c.comptime.lower fn)` already produces, which are
pure data, and which re-word-compile in about 10 us each. That still needs
the `Atom` and integer cache kinds named above, but it needs no story for
process addresses. It is a different milestone and is not scoped here.

### Consequences for the rest of the plan

M5 does not depend on M4: constant-argument folding needs the compile-time
form, which M1 already supplies. The M4 measurement in "Validation" and the
"Plan review" sentences that reason from literal-fold reuse and from a
per-function serialization diagnostic no longer apply.

## M5 - constant-argument folding

With both forms present, a call whose arguments are all compile-time
constants can be answered by the compile-time form at the call site. This is
the benefit that motivates emitting both, and it is the last milestone
because it needs M1 and nothing else needs it.

## Compatibility

`meta` is contextual, so no identifier breaks; the one in-tree use is a `List`
in an example and it keeps working. The decorator spelling keeps working
through M1-M3 and is removed only when the plan's own fixtures use `meta`.
`lib/autodiff.xmacro` is untouched. Whether the ported autodiff replaces it
remains Gary's call and is not part of this plan.

## Validation

Focused per milestone: `make build` clean with no new warnings,
`make verify-fixtures`, and `make verify`. The
`unittest/compiler-fixtures/comptime-*` fixtures are the ledger; every
milestone adds its entries there and regenerates `.stdout` by running the
built program. `make verify-fixtures-update` is never the way to make a
failure go away.

M4 needs one measurement rather than a count: the artifact's load-to-first-call
time with and without the serialized program, on a meta function that
qualifies.

## Plan review

**Facts the producers establish.** `_sdk_comptime_install` returning `%($fn)`
establishes that both forms already exist; M1 and M2 consume that rather than
re-deriving it. The importer already borrows `macro_lisp`, so M2 adds no
plumbing for the install and decides only emission. `lib/machine.x` states
that frozen constants do not own their pointees, which is why M4 rebuilds the
constant table instead of copying it.

**Deletion and reuse.** M3 expected to delete `_lower_coerce` and the
pre-transform conversion re-derivation; its scouting found the transformed
tree cannot carry a lambda or an interpolated string, so both stay and the
milestone is declined. M4 expected to reuse the literal-fold cache rather
than add a value serializer; its own scouting found the cache cannot
represent the constants, and it is declined too. Both are recorded above
rather than removed, because each names what a later design would have to
beat. The only lasting new mechanism is the contextual `meta` marker, and it
exists because the parser must know a fact before macro expansion that no
macro can tell it.

**Why this is idiomatic x2c.** `meta` sits where `static` and `inline` sit and
states the same kind of fact about a declaration. Contextual recognition
follows `keyword`, which is already contextual for the same reason. The
serialized program is a flat POD array emitted as a C static, which is how the
compiler already ships tables.

**Validators, diagnostics, and negative fixtures.** One new diagnostic: a
`meta` function whose word-compiled form does not qualify for serialization
reports why, because a silent skip would look like a performance bug later.
No new validator; a meta function that cannot link its runtime form is a link
error, which is the right failure and needs nothing added. No negative fixture
beyond the existing `comptime-declines-*` family.
