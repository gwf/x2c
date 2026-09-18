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

Today the lowering reads the pre-transform AST, because a `Unit` decorator
captures it. That forced `_lower_coerce` to re-derive conversions the compiler
already knows how to insert — `Array_list` at a declaration, `Symbol_str` at a
return — and each was a silent wrong answer before it was found.

With `meta` on the declaration the compiler chooses when to lower, so lower
the same typed tree the C emitter reads: one body, two backends. Delete
`_lower_coerce` and the pre-transform re-derivation with it.

Settle this before M4, because the serialized form should be produced from
whatever tree M3 selects.

## M4 - serialize the word-compiled form

Today `_auto_analyze` word-compiles an eligible Lisp lambda after two calls
and hangs the result on `lambda.auto_program` (`lib/lisp.x:1647`). Nothing
persists it, so every process pays for it again.

A frozen `MachineProgram` is one allocation holding four ints, then code,
constants and binders. The three sections serialize differently:

- **Code** is a flat `MachineWord` array, four `unsigned char` and two
  `short` each. It emits directly as a C static initializer.
- **Binders** are `Atom`. Emit their spellings and re-intern on load.
- **Constants** are `Var`, and `lib/machine.x` says plainly that the copied
  `Var` and `Atom` bits do not own their pointees. A constant holding a
  `List` or `String` is a pointer, so the table cannot be copied out; it has
  to be rebuilt. The compiler already rebuilds structured constants for
  folded literals through `Compiler.id_keys` and the literal cache, so reuse
  that path rather than writing a second value serializer.

Scope it honestly. Only a program that actually froze can be serialized;
`_auto_analyze` has eligibility rules and `MACHINE_CODE_MAX` is 4096 words,
so a large meta function may simply not qualify. Emit what qualifies, skip
what does not, and make the skip visible rather than silent.

Deliverable: a meta function's word-compiled form survives into the artifact
and is executed on load without recompilation, proven by a fixture that
observes the program is not rebuilt.

## M5 - constant-argument folding

With both forms present, a call whose arguments are all compile-time
constants can be answered by the compile-time form at the call site. This is
the benefit that motivates emitting both, and it is the last milestone
because it needs M1 and M3 and nothing else needs it.

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

**Deletion and reuse.** M3 deletes `_lower_coerce` and the pre-transform
conversion re-derivation, which exist only because the pass reads the wrong
tree. M4 reuses the literal-fold cache rather than adding a value serializer.
The only lasting new mechanism is the contextual `meta` marker itself, and it
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
