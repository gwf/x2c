# Meta functions

> Status: done - original milestones archived 2026-09-20.
> M1, M2 and M5-M8 shipped; M3 and M4 record measured declines. The shared
> parent, syntax builders and migration follow-ups reached dev through
> 21775a9d and b4e36b50; generated Lisp migrations continued through 231550b0.
> The new meta authoring and coverage campaign is active separately. The
> parked var-tags work and production-promotion boundary remain visible in
> [the index](../README.md); this archive is not a current execution plan.

## Original status context

The following notes describe the implementation at the time of this plan.
Current disposition is the status above.

> Objective set by Gary 2026-09-18: **replace essentially all hand-written
> compile-time Lisp with `meta` functions.** If it does not need to be Lisp,
> make it `meta`. Three exemptions and no others: the irreducible core that
> lowered code is written in, the name tables that map a lowered call to an
> operation, and anything an attempt shows to be genuinely problematic, with
> the evidence recorded the way M3, M4 and Phase 7 record theirs.
>
> Scoped 2026-09-18 on branch `x2c-lowers-to-lisp`, after Phases 0-4, 6 and 7
> of `plans/archive/comptime-x2c-generalization.md` landed and Phase 5 blocked on the
> capability this plan supplies. M1, M2, M5, M6, M7 and M8 are built, and M3
> and M4 are declined on evidence. The word and the
> three-lifetime design are Gary's decisions, taken 2026-09-18.
>
> **Delivery target: `dev`, not `main`.** The work reaches `main` through
> `dev` and only with Gary's explicit green light.

## Status, 2026-09-19

The integration branch is `lowers-integration`. It carries the milestones
above, the pre-merge fixes to the editor adapter ordering, two `_capture` and
`_free_names` repairs in `lib/lisp.x`, bare lambda parameter lowering, and
`List.get` agreement in `etc/comptime.xlisp`. It also carries the scratch-name
serial fix, which gives each macro template evaluation a process-wide name and
counts an import's fresh names apart from the unit's, and a latch that keeps
an exhausted compile-time call budget exhausted for the rest of its public
entry. `origin/dev` is merged in.

### Campaign follow-up, 2026-09-19

Lazy parent loading is delivered on `dev` at `df276ad4`. Across 60
interleaved runs, x2c.x hello-world translation measured 31.27 ms against
31.34 ms on old dev and 43.01 ms with eager preload. Bare hello measured
31.08/30.99/43.05 ms. The foreach case pays for restarting: 52.95 ms against
36.21 ms on old dev and 45.59 ms eager. All library and compiler C/H outputs
matched across batch, per-unit, and `-j 8` translation; editor tests passed.

The follow-up delivered at `c2eddebf` removes `$comptime()` and its install
hook. Existing
fixtures use `meta`; autodiff passes one Map through reverse-mode helpers
instead of using file-scope state. Array and Map foreach cursors now use
frame slots when their storage stays inside the loop block. Other cursor
calls retain the ordinary pointer path. Six interleaved real translations
showed unchanged library time within noise and compiler-source translation
3.164 to 2.910 seconds, with identical generated C/H. A separate Array/Map
workload measured 352 to 77 ms. Suffixed float literals now round at float
precision before widening; differential coverage includes f/F and hex floats.

**The 11 syntax builders** now have one `meta` body each in `lib/meta.x`.
The shared parent binds both spellings to that body, with checked adapters
for the three Lisp literal spellings and a rest-argument adapter for
`x2c.expr.call`. Nine builders also run at runtime, while
field and cast construction retain their compiler-query restrictions.
Preloading installs native operations first. Cold declaration collection
uses the three literal builders' native forms, compiled from those same
bodies, until the lowered forms replace them. Source keys are canonical,
and a failed preload stops instead of freezing a partial session. Fresh
compiler passes inherit restrictions from existing shared lowering records.

The builder integration is delivered on `dev` at `44fa25e3`. The full
`agent-pr-check` passed, including 928 unit tests, 743 compiler fixtures,
556 raw-symbol comparisons, self-host checks, and 66 documentation examples.
Editor direct and worker checks also passed.

Gary approved the literal argument adapters and staging on 2026-09-20.
Staging DNS, HTTPS, domain ownership, and the repository-scoped publisher App
are configured. Candidate build `35510273856` selects the exact delivered
source `44fa25e30ed593683c7e4269d41af2b0bec47842`. Staging run
`35510839910`, attempt 2, deployed that candidate and passed installation
verification on Linux and macOS, on both Intel and ARM. Production promotion
remains a separate decision.

### Parked

**The var-tags port** stays on branch `report-var-tags` at `b96fc24d`.
The collection-only body-skip prototype did not meet Gary's condition that
removing repeated parsing cut roughly half the port's translation overhead.
Neither the port nor that skip machinery is delivered.

Measured on `df276ad4` with shared-parent native registration and canonical
filename keys repaired, using real source homes and their built preludes.
Both macro files had the same harmless post-build edit to match import-cache
state. One warmup preceded six interleaved measurements with other agents
paused. All 182 library/compiler C/H outputs matched between the port with
and without skipping, and header-cache probes passed.

| Batch | No port | Port | Port + body skip | Overhead removed |
| --- | ---: | ---: | ---: | ---: |
| 57 library units | 2.302 s | 2.576 s | 2.572 s | 1.39% |
| 34 compiler units | 3.154 s | 3.348 s | 3.297 s | 26.02% |

Library IQRs were 40.5/18.9/16.4 ms, so the 3.8 ms improvement is below
noise. Compiler IQRs were 16.5/12.8/11.0 ms; its 50.4 ms improvement remains
below the acceptance condition. A temporary counter confirmed the skip ran
43 times for `varconvert.x`; it was removed after the experiment. Earlier
copied-home timings lacked a normal prelude and are not acceptance evidence.
The retained prototype is in worktree branch `codex/var-tags-probe`.

### Decided

A `let` binding is not visible inside its own initializer. A compile-time Lisp
helper that calls itself by name must be a `defun`. This is the lexical rule,
not a defect. It is stated in the language reference and in the meta-functions
chapter.

### Open

- Keep the var-tags port parked until a measured approach meets its condition.
- Promote to production only with separate authorization.

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

Earlier drafts of `plans/archive/comptime-x2c-generalization.md` asserted that a
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

`meta` composes with a storage class rather than replacing one, and never
decides one. `static` still says only what it always said about the runtime
form, which is emitted where a unit reaches it.

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

## M2 - the import loop (done)

The macro-import loop in `src/macros.x` now accepts a `meta` declaration
beside a keyword definition, a macro definition, and a top-level `$(...)`
form. The branch calls `Compiler.parse_top_level`, so M1's marker performs
the install; the importer already borrows the caller's `macro_lisp`, so it
lands in the consuming unit's session.

**The emission rule: a unit emits the runtime definitions it reaches, and
the storage class the author wrote stands.** The two lifetimes are separated.
Every importing unit installs the compile-time form, which emits no symbol.
The runtime definition is emitted only where the unit's own code reaches the
function, directly or through another meta function it emits; a unit that
calls one only during translation emits nothing for it. `static` then gives
that unit its own copy, and its absence names the one public copy the program
links, exported by the reaching unit's generated header.

The first `static`-only rule was withdrawn by Gary on 2026-09-18. `static` is
a statement about the runtime function alone, and a marker that decides it
conflates the two lifetimes the word `meta` exists to keep apart.

`Compiler.parse_macro_lisp_top_level` still returns the definitions a macro
import contributed as a `%(seq ...)`, including a nested import's.
`Compiler.parse_top_level` now retains them in `c.meta_defs` instead of
handing them to the unit driver, and `Compiler.full_parse` appends the
reached ones after the unit is parsed, since only then is reaching decided.
`_collect_binding_references` records every binding an `(ident (binding ...))`
names. One meta function calls another, so the retained definitions are then
walked once from the last back: the import loop takes a definition and
refuses a prototype, so a meta function calls only ones declared before it
and no second pass can add anything.

### Where the single public definition lives

A public imported `meta` function needs one home, and no unit is a natural
owner: a `.xmacro` is not a translation unit, and picking the first importer
would depend on build order, which breaks incremental and parallel builds.
The answer is the one the macro families already use, and it needs no new
spelling.

`$array.typed.family(ArrayDbl, double, 0.0, "ArrayDbl")` is invoked once, in
`lib/typed-array.x`. That produces exactly one `double ArrayDbl_push(...)` in
`bootstrap/lib/typed-array.c` and its prototype in the generated
`typed-array.h` (checked 2026-09-18); every consumer links that one copy.
Nothing in the compiler enforces the "once": invoking the same public family
in a second unit gives a duplicate symbol at link. The single home is the
author's, designated by writing the invocation in one unit.

A meta function is designated the same way, by the **run-time call**. The
disanalogy is why it has to be: a family macro's body reaches only the unit
that invokes it, while a meta function's body is parsed in every importer,
because that is how the compile-time form is installed. So the importers
cannot be distinguished by who has the definition - they all do - and they
are distinguished instead by who calls it. One unit reaches it, owns the
public copy, and exports it; every other unit reaches it only during
translation and emits nothing.

The limit, measured: if a second unit also reaches the same public meta
function, the two copies collide. Probed 2026-09-18 with `meta-import.c` and
a second unit calling `mi_constant`: `ld` reports
`duplicate symbol '_mi_flatten'` and names both objects. That is the same
failure a twice-invoked public family gives, it names the function, and the
plan already called it the right one. An author who wants many run-time users
inside the import set writes `static` and gets a copy each.

The alternative was a designation spelling - a top-level form naming the unit
that owns the runtime copies, with prototypes emitted in the others. It buys
"once for everyone" *within* the import set, and it costs a new compile-time
form, per-unit designation state, synthesized prototype emission, and two
failure modes the compiler still cannot catch (nobody designates, two units
designate). Nothing in the repository wants it yet: `lib/autodiff.xmacro` is
Lisp, and every meta function in the fixtures is either `static` or reached
by one unit. Add it when a `.xmacro` ships a runtime helper several units
call, not before.

Three facts the work established.

- **The importer has to borrow more than `sym` and `fn_defs`.** Binding real
  x2c in the import touches the unit's literal cache and its protocol
  registries. Without the literal cache the emitted body's `(cache id)`
  references index the wrong table, which produced a silently wrong string;
  without `protocol_helpers` a converter check wrote to a null `Map` and
  aborted. `Compiler.borrow_unit_semantics` now shares all of it.
- **The import cache had to learn about them.** A unit whose shallow pass
  produced a declaration bundle keeps `c.imports` into the full parse, so
  the cached entry answered and nothing was emitted. The entry records
  whether the import contributed `meta` definitions; when it did, the first
  import in each pass reads the file again rather than replaying definitions
  bound in the previous pass's symbol table.
- **The lowering's callee surface is `etc/comptime.xlisp`, not
  `etc/lisp-values.xlisp`.** `String.count`, `String.partition` and
  `String.remove_prefix` are bound as values but have no `String_*` name for
  the pass to find, so a body using one declines. Widening that list is its
  own change.

The fixtures own the emission evidence. `meta-import.phases` declares `h`
and `c`, so `meta-import.h` and `meta-import.c` are checked in: the header
exports `String mi_flatten(String path, String sep)`, the C defines it once
and defines the four `static` functions the unit calls, and neither file
mentions `mi_tag`, which only `$probe.tag` calls. `meta-import-second.x`
imports the same file and its checked-in C defines only `mi_depth` and
`mi_dashed`. `comptime-declines-meta-import` is gone with the refusal it
pinned.

This unblocks `plans/archive/comptime-x2c-generalization.md` Phase 5 and reopens its
Phase 7 verdict. Do not re-scope either until Gary asks.

One defect surfaced here and **fixed during integration**: a character
literal in a compile-time function lowered to garbage. `meta int f(void) =>
'A';` answered 65 at run time and a different large number on each
compile-time run, so a body that tested characters was a silent wrong answer.

The cause is the trap this branch keeps hitting for the third time: `*` is a
sequence binder in a pattern, so `(* char)`, which selects a C string, also
matches a plain `(char)`. A character therefore reached `_lower_text`, which
returned the spelling itself to be read as a number. `_lower_text` now decides
on the spelling's own quote and answers a character's code, `'\n'` included.
Covered by the `character` row in `comptime-lowering.x`, which prints each
answer beside the same function's run-time answer: `65 65  10 10  1 1`.

## The install cost, and what it costs now (fixed)

Measured 2026-09-18 on branch `meta-install-cost`, after M2. A `.xmacro`
holding 44 one-line definitions, imported by a unit that calls none of them
at run time, made an imported `meta` function cost about fifteen times what a
Lisp `defun` costs, paid by every importing unit. `lib/var-tags.xmacro` has 32
importers, which is what made Phase 5 of
`plans/archive/comptime-x2c-generalization.md` a net loss.

**Where the time went.** Split with a sampling profile of one translation of a
4400-definition import, and confirmed by a hit/miss probe:

- About half is the x2c parse of the declaration and its body.
- About half is `Compiler.lower_comptime`, dominated by the two `_lower_scan`
  passes and `_lower_stmnt`.
- The install itself - evaluating the `def` forms in the session - is about
  1%. It was never the cost, despite the milestone's name.

Each importing unit pays this **twice**: the collection pass and the full
parse each read the import and each parse and lower every definition. Only the
collection pass discards the syntax it produced.

**What a process can share.** `make build` translates a stage in one
`x2c translate` process, and `translate` defaults to one job, so one process
sees every unit; `x2c build` forks one worker per unit, where the same cache
still removes the second pass. Nothing was shared before this: `c.imports` is
per unit, and its entry records only whether an import contributed `meta`
definitions, which is what makes the second pass read the file again.

**What is safe to share.** The lowering reads the unit through exactly two
things. `_lower_constant` dereferences a `(cache id)` into the literal's
value, so no unit-relative id survives into the forms. `_lower_known` asks the
unit's Lisp session whether a callee is bound, which is the one input that can
differ; the names it resolved are recorded with the entry and rechecked on
reuse, so a unit whose session lacks one lowers again and reports the same
refusal. Generated names are safe: `lower_counter` already runs across the
process and only advances, so a name minted for a cached entry is never minted
again.

**The fix.** `src/comptime.x` keeps a process cache of lowered forms, keyed by
the file and the name the author wrote, in the idiom `src/collect.x` already
uses for its process cache: a `Scope` with a shutdown hook, and `try_own` to
promote each retained entry past every per-unit `Context`. A lowering holding
a wide numeric leaf - what a literal too large for an `int` produces - is not
retained, because its box belongs to the unit's `Scope` and promotion to the
value pools does not reach it.

**Result**, before and after, as the minimum of interleaved runs of the two
compilers on one host. The one-unit column is the wall time `x2c translate`
reports; the 32-unit column is CPU time for one process translating 32 units
that import the same file. The host was busy, so read the differences between
rows rather than the absolute numbers: with the same runs, a row that should
not move moved by 2 to 5 ms.

| the import holds | 1 unit | 32 units |
| --- | --- | --- |
| nothing | 61 -> 59 ms | 1119 -> 1124 ms |
| 44 Lisp `defun`s | 66 -> 68 ms | 1175 -> 1180 ms |
| 44 `meta static` | 91 -> 86 ms | 1905 -> 1559 ms |

Per declaration per importing unit, across the 32 units: 0.56 ms before,
0.31 ms after, against 0.04 ms for a Lisp `defun`. A 44-function `var-tags`
port over its 32 importers costs about 0.44 s of translation instead of
0.79 s. One unit gains little, because only its second pass can hit a cache
the first pass just filled; the gain is across units, which is where a build
spends the time.

What is left is the parse, still done twice per unit. Removing the second one
means the collection pass not parsing `meta` bodies, and the collection pass
is where the install has to happen for a macro expanded during collection.
That is a separate change and was not attempted here.

## `foreach` in a macro import (fixed)

A `meta` function in a `.xmacro` could not iterate a concrete collection:
`foreach` over a `List` reported "type (\"List\") is not iterable", while the
same body in a `.x` unit worked. The cause is not a missing shared field.
`_shallow_parse_loop` opens with `c.rebuild_protocols(NULL)` and
`c.conforms = {}`, because the collection pass parses no bodies and needs no
conformances - except that a `meta` definition in an import is the one body it
does parse, and `foreach` reaches a collection's `iter` member through the
conformance registry. A unit's own `meta` function is unaffected because
collection skips its body and installs it only during the full parse.

The import now installs the protocols and adoptions visible to it into its
own compiler, the first time `Compiler.protocol_members_for` is asked for a
member, and that call resolves the one adoption it needs. The caller's
registries are left alone, since the full parse rebuilds and resolves them
anyway. The first arrangement tried resolved every visible adoption instead of
the one asked for, and cost a third of a translation - more than the whole
feature - so both halves are on demand. `List`, `Array` and `Map` all iterate
now; `meta-import-defs.xmacro` covers the `List` case.

A `Var` collection still declines, with "no binding for Iter_try_next". That
is not a missing entry in `etc/comptime.xlisp`: the `Var` branch of `foreach`
expands to `Iter iterator = Var_iter(collection, &storage)` and a
`Iter_try_next(iterator, &item)` loop, and neither `Var_iter` nor `Iter` has a
compile-time representation. Deciding one is its own change.

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

## What M3 and M4 together establish

Both milestones were declined on evidence, and the two declines say the same
thing from opposite ends: the word-compiled program and the transformed tree
are each a lowering toward one target, and neither carries what compile-time
code needs.

The transform is a lowering toward C. It replaces a lambda with a `Func`
handle and leaves the body in a separate static the AST does not associate
with it, and it turns an interpolated string into raw C text - the literal
fragment `"String_join(NULL, "` appears in the tree as a string. So the
pre-transform tree is the correct input for this pass, and `_lower_coerce` is
not a wart to be deleted: re-deriving `Array_list`, `List_array` and
`Symbol_str` is the price of reading the tree that still has the source's
meaning. It stays, and the plan review's claim that M3 would delete it is
withdrawn.

The word program is a lowering toward the machine. It holds live process
addresses and resolves callees by name through the Lisp session, so it is an
accelerator for a session rather than a portable artifact.

The consequence for the third lifetime in "The result": shipping a meta
function to an interpreted runtime means shipping the **lowered Lisp**, not
the word-compiled form. Word compilation then happens on load, at roughly
10 microseconds per program. Nothing in this plan builds that, and nothing
needs to until a runtime asks for it.

## M5 - constant-argument folding (done)

With both forms present, a call whose arguments are all compile-time
constants is answered by the compile-time form at the call site.
`Compiler.fold_meta_call` in `src/comptime.x` runs from `_finish_call` in
`src/expressions.x` and returns either the answer as a literal or `NULL`,
which leaves the call. Leaving the call is always correct, so every
uncertainty declines that way.

`_finish_call` is the only place the pass needs. It is the single funnel every
call resolution ends at, it holds the resolved callee with its binding, the
function type with its parameter types, and the arguments as bound
expressions; and it runs before `Compiler.transform`, on the tree that still
has the source's meaning. `Compiler.id_keys` is reachable from there through
the compiler, which is what lets a `(cache id)` argument be read back.

### What counts as a constant argument

The reader is `_lower_constant`, which `src/comptime.x` already uses inside a
`meta` body: integer, floating, character and string literals, a `Symbol`
literal, and the `(cache id)` a folded constant leaves behind. A `(cache id)`
does qualify. `Compiler.cache` interns only `cons`, `var`, `string` and `nil`
keys, so the graph behind one is immutable compiler-owned data and the
run-time call receives the same graph the reader returns. Measured in
`meta-folding.x`: `mf_width("abcd", %(a b))` folds to `6`, where the `List`
argument reaches the reader only as `(cache 4)`.

An argument is used only when the parameter's type and the argument's type
resolve to the same key through `Sym.resolve_key`. That is one comparison
rather than a promotion table, and it keeps the int-to-double promotion a
mixed conditional would apply out of the pass entirely: `f(3)` against
`double f(double)` declines instead of guessing. It still accepts a `char *`
literal for a `String` parameter, because `String` is `char *`.

### What the result can be substituted as

An `int`. That is the one return type whose value spells itself as the same
literal an author would have written, and the milestone's own example returns
one. The others were declined and the reasons are worth keeping:

- A `String`, `List` or `Map` result has no literal form that also carries the
  ownership the call would have returned. The run-time form of
  `meta String mf_label(int n) => %"row-$n";` returns a value its caller may
  free; the interned literal a fold would substitute is not one, so the two
  are not observably identical and `mf_label(4)` stays a call.
- A narrower or unsigned integer result would need the C conversion written
  into the substituted syntax, and a floating result would need a text
  round-trip. Neither has a user yet.

A negative result is parenthesized, so a folded `-4` after a `-` cannot join
into `--`.

### The two forms have to agree

- **File-scope state.** `_lower_read` lowers a non-local read to
  `C.gread`, which reads the session's own `C._globals`; no unit initializer
  writes it, so a `meta` function that reads a file-scope variable answers
  differently in its two forms. The lowering records that it reached
  file-scope state and `_lower_scan_call` gives every caller the same reach.

  Recording such a function as impure rather than foldable was not enough,
  and it was **corrected**: folding declined, but a macro calling the same
  function still took the session's answer with nothing said. A `meta`
  declaration that reaches file-scope state is now refused outright, since
  `meta` is the word for a function whose two forms agree. The `$comptime()`
  decorator promises one form and keeps the state, which `ct_next` and
  `ct_discard` in `comptime-lowering.x` exercise; `install_comptime` records
  the reach for either spelling, so a `meta` function calling a decorated
  impure one is refused too. `comptime-declines-meta-globals` pins the
  refusal, and `meta-folding.x`'s `mf_offset` and `mf_shifted` are gone with
  the rule they illustrated - `mf_narrow` took their place, showing a result
  type that is left alone rather than a body that disagrees.

  The `const` exemption a review asked for is not available: a file-scope
  initializer is unit syntax that the symbol table does not keep, so nothing
  at lowering time can tell a `const` variable's value from a mutable one's.

- **An enum constant.** Same shape, found the same way: an enumerator is an
  `ident` whose binding the function does not declare, so it reached
  `C.gread` and answered zero. Its value is not available either -
  `Sym.declare_enumerator` records the owner and `Sym.declare` the enum
  type, and the number stays in the enum declaration's own syntax - so the
  lowering refuses it by name. `comptime-declines-meta-enum` pins it.
- **A raise or a decline.** The evaluation runs under a `catch` that returns
  `NULL`, so a compile-time failure leaves the call. A lowering that declined
  never installs, so its function is never foldable.
- **Arithmetic.** A lowered operator goes through `Var_binary`, the same
  operation the runtime uses, so 32-bit wraparound, integer division and
  remainder agree. Probed against the same calls with a local argument:
  `7/2`, `-7/2`, `7%2`, `40000<<20` and `100000*100000` fold to exactly what
  the emitted call returns.
- **Across units, not at all.** `meta_folds` is keyed by binding id and lives
  on the compiler that declared the function, and a macro import parses on its
  own child compiler, so an imported `meta` function never folds. That is not
  only the stated rule: M2 designates the unit that emits a public imported
  definition *by its run-time call*, and folding that call would make emission
  depend on whether the call's arguments happened to be constant.
  `meta-import.c` and `meta-import-second.c` are unchanged, `mi_depth("a.b.c")`
  included.

The `$comptime()` decorator spelling does not fold. Its install runs from a
Lisp native on a definition that is spliced back and re-bound afterwards, so
the binding the call site resolves against is not the one the install saw.
`comptime-lowering.x` prints `mt_poly(7)` beside `ct_poly(7)` and the
generated C shows `71` against a call, which is the contrast.

### What it costs and what it leaves

`fold_meta_call` returns on an empty `meta_folds` before it allocates, so a
unit with no `meta` function pays one `Map` length test per call resolution.
`comptime-autodiff.x`, whose 106 compile-time functions are all `$comptime()`,
translates in 0.94 s before and 0.95 s after, five interleaved pairs of the
two compilers on the same tree, which is the benchmark's own noise. Timing
the two builds in separate sessions read +2%, and the interleaved pairs are
why that number is not recorded as a cost.

One consequence to know about: a `meta static` function whose every call folds
is emitted and never called, which is dead code a `-Wall` build would name.
Not emitting it would mean extending M2's reachability walk to a unit's own
definitions, where `static` means something the author wrote rather than
something the pass decides. Left alone.

### Evidence

`unittest/compiler-fixtures/meta-folding.x` declares `c` in its `.phases`, so
its generated C is checked in, and that C is the proof: the answers are equal
either way, which is the point. `comptime-lowering.x` carries the ledger rows.
`comptime-lowering.phases` stays `stdout status`; pinning its 1312 lines of
generated C would churn on every unrelated emission change, and the small
fixture says the same thing.

## M6 - the compiler surface in x2c (done)

Gary's decision, taken 2026-09-18. The SDK a macro implementation calls was
reachable only from Lisp: `x2c.ident`, `x2c.source.text`, `x2c.type.fields` and
the rest are `$lisp.bind` rows in `src/macros.x`, and `x2c.function.name` did
not resolve from x2c source at all. That was the one place where Lisp was the
authoring language rather than the engine, and it is why the first Phase 5 port
left `dedent.expand` in Lisp. The implementations already existed in x2c as the
private `_sdk_*` statics; they needed declaring, not writing.

`lib/meta.x` declared them under a `Meta` namespace - `Meta` was free as a type
name - and `etc/comptime.xlisp` maps each mangled name to the operation the
compiler already binds. With that, a macro body is one call and the
implementation is x2c:

```x2c
meta static List ms_fields(List receiver) =>
  x2c_type_fields(x2c_syntax_type(receiver));
```
```lisp
(defun Meta_type_fields (value) (x2c.type.fields value))
```

The rows are `defun`s rather than `def`s, which the design called for. The
natives are `$lisp.bind`ed **after** every library file is read, so
`(def Meta_ident x2c.ident)` fails at load with `(unbound (name x2c.ident))`. A
`defun` resolves at call time. The forwarding layer is also where the two
shape adjustments live, below.

**Superseded 2026-09-19.** Gary decided the x2c spelling is a plain function
`x2c_<path>`, so `Meta.type_fields` is `x2c_type_fields`, and the Lisp names
stay dotted and unchanged. The `Meta` namespace type and all 31 forwarding
`defun`s are gone. The lowering maps `x2c_a_b` to `x2c.a.b` mechanically, with
four exceptions: `x2c.type.tag-name` and `x2c.type.reverse-name` carry a
hyphen, and `x2c_expr_call` and `x2c_type_value` keep an adapter in
`etc/comptime.xlisp` under `_x2c.expr.call-list` and `_x2c.type.value-int`.
The derivation below is superseded with it: a callee with no definition whose
mapped Lisp operation the session binds is a compiler operation, so giving one
of these declarations a body makes it an ordinary function.

### What is exposed, and what is not

Thirty operations: the 16 public `x2c.*` bind rows other than
`x2c.comptime.install` and `x2c.comptime.lower`, plus the 14 public wrappers in
`etc/compiler-sdk.xlisp`. Each group earns its place by the question a macro
implementation cannot answer without it.

| group | operations | why a macro needs it |
| --- | --- | --- |
| identifiers and literals | `ident`, `literal_string`, `literal_int`, `literal_symbol` | the only way to hand an answer back as syntax |
| expression construction | `expr_ident`, `expr_index`, `expr_field`, `expr_call`, `expr_composite` | a rewrite needs the shape, not text, because the compiler binds and types the result |
| reading the capture | `source_text`, `binding_spelling`, `syntax_type`, `cache_value` | four questions about received syntax that walking the `List` cannot answer |
| reading a function | `function_name`, `function_parameter`, `function_body`, `parameters_arguments` | what a decorator takes apart and forwards |
| reading a type | `type_fields`, `type_layout`, `type_parts`, `type_resolve`, `type_value`, `type_tag_name`, `type_reverse_name`, `method_resolve` | the answers live in the symbol table, not in syntax; this is the group a macro family needs |
| the invocation site | `invocation_file`, `invocation_line`, `invocation_column`, `embed_text` | where the developer wrote the call, and what is beside it |
| failing | `diagnostic_fail` | says what is wrong at the site, which no return value can |

Left out, with the reason:

- **`x2c.comptime.install` and `x2c.comptime.lower`** recurse into this pass.
- **The `_x2c.*` privates** - the `foreach` helpers, `_x2c.function.reference`,
  `_x2c.function.native-type`, `_x2c.type.integral?`, `_x2c.type.pointer?`,
  `_x2c.type.element`, `_x2c.type.parameters`, `_x2c.type.return`,
  `_x2c.literal.string`, `_x2c.symbol-set`, `_x2c.import-hook`. The language
  reference already states that a component beginning `_` is a private
  implementation detail; exposing them from x2c would make thirteen of them
  public without a caller asking.
- **`x2c._fail`, `x2c._params` and `x2c._arg`**, the private wrappers, for the
  same reason. `x2c._fail` is one line over `diagnostic_fail`.

Two shapes needed adjusting rather than aliasing, and both adjustments are in
the forwarding `defun`:

- **`x2c.expr.call` takes a rest parameter**, which no x2c prototype can
  spell. `x2c_expr_call(List callee, List arguments)` takes the `List` and the
  row spreads it with `apply`, which is what a Lisp caller writes anyway.
- **`x2c.type.value?` answers a Lisp truth value**, and the x2c surface returns
  `int`, whose test `_lower_truth` inlines as a comparison against zero. Nil
  compares unequal to zero, so an unnormalized alias would have made
  `if (x2c_type_value(t))` true for "no". The row answers 1 or 0, the way
  `List_equal` does.

**The `void` hazard does not apply to this surface, which was checked before
aliasing.** `Array_getindex`, `Map_get`, `List_get`, `List_last` and
`List_assoc` are wrapped in `etc/comptime.xlisp` because their x2c operations
answer `void` for an *absent* element, which has no Lisp value. No SDK
operation does that: where there is no answer it answers nil
(`method_resolve`), and where the request is wrong it rejects. A reject is the
SDK's designed failure channel and it reaches the developer as a located
diagnostic even from inside a lowered `meta` function. Probed 2026-09-18:
`x2c_type_fields` on an `int` reported
`x2c.type.fields requires a struct or union Type` with `note: value: (int)` at
the macro invocation, and exited 1.

### Compile-time only, derived rather than spelled

These operations exist only inside a compiler, so a `meta` function that
reaches one has **no valid runtime form**. There is no `meta only` keyword: a
spelling would be a second source of truth for a fact the compiler can see.

M5 already built this mechanism for a different property, and M6 reuses its
shape rather than inventing a second propagation. Where M5 records
`lower_reached_globals` from `Lowering.globals`, `meta_impure` by name, and
spreads it in `_lower_scan_call`, M6 records `lower_reached_meta` from
`Lowering.meta_only`, `Compiler.meta_comptime` by name, and spreads it in the
same place. `_lower_scan_callee` gained two lines.

The derivation itself is the namespace: `_lower_compiler_operation` answers
whether a callee's binding spelling begins `Meta_`, because `Meta` names this
surface and nothing else declares into it. One constant, one place.

`Compiler.install_meta_function` is now a three-way choice. A function that
reaches a `Meta` operation is compile-time only; otherwise one that reaches
file-scope state is impure; otherwise it folds. Compile-time only comes first
and excludes folding, which matters: `fold_meta_call` runs from `_finish_call`,
where `macro_sdk_compiler` is null, so every SDK operation would reject. The
catch would swallow the raise and leave `macro_sdk_failure_message` set, and
`_report_lisp_failure` would then report that stale message on the next
unrelated failure.

A run-time call to such a function is refused at the call.
`Compiler.check_meta_call` runs from `_finish_call` and names the function,
which the link error it replaces did not: `Undefined symbols ... _mi_tag`
names the C spelling and no source position. A body parsed under the `meta`
marker is exempt, because calling a compile-time-only function is what makes
its caller one too; `Compiler.meta_body` carries that for the parse.
`meta-comptime-only-call` pins both halves.

Emission is refused in the two places a runtime definition can arrive.
`Compiler.parse_top_level` returns `NULL` for the unit's own compile-time-only
definition, the way it already does for a keyword definition, so nothing enters
the unit's AST and no prototype reaches the header.
`_append_meta_definitions` skips an imported one. A unit that calls such a
function at run time gets the link error that names it, which is the failure
the plan already called the right one.

One thing had to change in the import loop for this. `_import` decided "this
file contributed `meta` definitions" from the count of runtime definitions it
collected, and that flag is what makes the next pass read the file again rather
than replay a cached entry - which is how the install happens in each pass. A
file whose `meta` functions are all compile-time only contributes no runtime
definition, so the count was zero and the install was skipped on the second
pass. `_import` now records that it *installed* one, and answers an empty
`%(seq)` rather than `NULL`.

### The lowering cache had to carry the facts

The process cache `src/comptime.x` added for the install cost returns 1 from
`Compiler.install_comptime` without lowering, so `lower_reached_globals` held
whatever the previous lowering left. That is a pre-existing defect of the cache
- an imported function's impurity was read from the wrong lowering - and
M6 cannot inherit it, because a stale answer here decides emission. The entry
is now `(forms callees globals meta)` and a reused entry restores both.

### One defect found and fixed

`String.join(sep, someArray)` inside a `meta` function aborted the compiler:
`x2c error floor: <bad-types>: error detail contains an identity-bearing
value`, exit 134, no diagnostic. Reproduced 2026-09-18 with an eight-line
function and no `Meta` operation involved, so it predates this milestone.

The cause is an inventory that was one entry short. `_lower_coerce`'s own
comment said "a declaration and a return both name a type the value has to
reach, and neither carries the conversion the transform would insert later ...
so this sees only the two places that do not." An **argument** is a third such
place: the x2c type system converts at a converting destination - writing
`.list()` there earns the `unnecessary conversion` warning - and the lowering
passed the `Array` straight through, so `String.join` received an `Array` where
it wanted a `List` and raised with the value in the detail.

`_lower_args` now takes the callee's parameter types out of the call's
signature and coerces each argument through `_lower_coerce`, which adds no
pair: the closed list of `Array`/`List`, `List`/`Array` and `Symbol`/`String`
is what it was. `parameters` runs out before `args` for a variadic callee,
whose extra arguments name no type to reach. The only behaviour that changes is
the three pairs, each of which produced a wrong type before.

### Evidence

`unittest/compiler-fixtures/meta-sdk.xmacro` and `meta-sdk.x`, modelled on
`meta-import.*`, with `c stdout status` in the `.phases`. The macro bodies are
one call each; the implementations are x2c. The checked-in `meta-sdk.c` is the
proof of the emission rule:

```c
static int ms_total(int a, int b, int c);
static String ms_label(String name, int n);
...
  int reads[3] ={ p.x, p.y, p.z };
  printf("names    %s\n", _1);              /* "x, y, z" */
  printf("count    %d\n", 3);
  printf("total    %d\n", ms_total(p.x, p.y, p.z));
  printf("spelling %s\n", _2);              /* "p.y + 1" */
  printf("label    %s\n", ms_label(_3, 7));
```

`{ p.x, p.y, p.z }` and `ms_total(p.x, p.y, p.z)` were built by
`x2c_type_fields`, `x2c_syntax_type`, `x2c_expr_field`, `x2c_expr_composite`,
`x2c_expr_call`, `x2c_expr_ident` and `x2c_ident`; `"x, y, z"` and
`"p.y + 1"` by `x2c_literal_string` and `x2c_source_text`; `3` by
`x2c_literal_int`. The file defines `ms_total`, which the unit wrote itself,
and `ms_label`, the one `meta` function that reaches no `Meta` operation and so
keeps both forms. It mentions none of `ms_fields`, `ms_field_reads`, `ms_reads`,
`ms_total_call`, `ms_names`, `ms_count` or `ms_spelling`, and the program prints
the same answers a runtime implementation would.

### What it costs

`make build` is clean with no new warnings, `make verify-fixtures` reports 727
passed against 726 before - the new fixture - with `comptime-autodiff.stdout`
byte-identical, and `make verify` reports 915 passed, 0 failed.

Two measurements, each the minimum of interleaved runs of the two compilers on
one host whose load average was about 9, so read the difference between the
columns rather than the absolute numbers.

| what | without M6 | with M6 |
| --- | --- | --- |
| `comptime-autodiff.x`, 106 compile-time functions | 928 ms | 921 ms |
| `meta-import.x`, the 30 rows' own session cost | 81 ms | 80 ms |

The first is eight interleaved pairs and isolates the compiler change,
including the extra `_lower_coerce` per argument. The second swaps
`etc/comptime.xlisp` under one binary, so it is the cost of evaluating 30 more
`defun` forms in every compile-time Lisp session; it does not register.

Both binaries have to sit in `builds/0` for this. The same binary run from
`debug/bin` translated `comptime-autodiff.x` in 1.5 s rather than 0.93 s,
because the repository root it discovers decides whether it replays
`lib/x2c.xi` as the prelude.

## Compatibility

`meta` is contextual, so no identifier breaks; the one in-tree use is a `List`
in an example and it keeps working. `Meta` becomes a reserved type name only in
a unit that includes `lib/meta.x`, which is not in the implicit prelude. The decorator spelling keeps working
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

## M6 - the x2c surface onto the compiler (done)

Landed as `da334992`. 30 operations in `lib/meta.x` under a `Meta` namespace,
each forwarded in `etc/comptime.xlisp` to the operation the compiler already
binds: the 16 public `$lisp.bind` rows other than `x2c.comptime.install` and
`x2c.comptime.lower`, plus the 14 public wrappers from
`etc/compiler-sdk.xlisp`. The private `_x2c.*` names are left out.

This closes the gap that made the first Phase 5 port partial. A macro's
implementation can now ask the compiler things from x2c instead of dropping
into Lisp, so `dedent.expand`, `var-tags`' six SDK calls and `varops`' two
become portable.

Two rows needed shaping rather than aliasing, and the second is worth knowing:
`x2c.expr.call` takes a Lisp rest parameter, so its row spreads a `List` with
`apply`; and `x2c.type.value?` answers a Lisp truth value, which an `int`
surface would have read wrongly, because `_lower_truth` inlines an `int` test
as a comparison against zero and nil compares unequal to zero. The row answers
1 or 0. The rows are `defun`s rather than `def`s because the natives are bound
after every library file is read.

A meta function reaching a `Meta.*` operation is **compile-time only** and its
runtime form is not emitted, derived transitively through the mechanism M5
already built for file-scope state. No keyword, one constant, one place.

## M7 - callable values (done)

**The pass recognises the expansion and collapses it.** That was the first of
the two shapes this milestone offered, and it is the right one, because the
second is already true: a `Func` in a compile-time function *is* the Lisp
lambda the pass lowered, so there is nothing to convert and the only work is
reading the callee and the arguments back out of the expansion.

`f(x)` is not a call in the AST. `_resolve_func_call` in `src/expressions.x`
turns it into a statement expression that stores the callee, queries a
reference carrier per argument through `x2c_func_reference_type`, boxes each
argument into a `FuncArg`, and reaches `Func_apply` last; a call with no
arguments needs no locals and is the bare `Func_apply`. `_lower_func_parts` in
`src/comptime.x` recognises both spellings and answers the callee followed by
each argument's value form. `_lower_application` lowers that to `(callee
arg...)`, which the evaluator applies the way it already applies a lambda this
pass puts in head position.

**The recognition has one owner because the scan needs it too.** Scanning the
expansion would read the reference branch's `&argument` as an address-taken
local and put an ordinary parameter in a cell, and would refuse the function
over the four callees the expansion names - which is what `no binding for
Func_apply` was. The scan now scans the application instead. The argument
count `Func_apply` receives cross-checks the groups the recognition found, so
a block of another shape answers nothing rather than a truncated call.

**The reference branch is dropped rather than lowered**, and that is the one
place the two forms of a `meta` function can disagree. A `Func` whose
signature declares a reference parameter takes that branch at run time and its
value branch at compile time. Every `Func` a compile-time session can produce
is a lowered lambda over values, where they agree. An argument whose type has
no `Var` tag cannot cross at all - `x2c_func_unrepresentable_argument` stands
in for the boxing - and that is refused with its own wording, verified against
a function-pointer argument.

**A function named where a value is wanted is the other half**, and without it
only a lambda could produce a compile-time `Func`. `Func g = mt_bump;` lowered
to `C.gread` on the function's binding id, which read nothing and produced
`(not-call (actual integer))` at the call - a wrong answer, not a decline. A
non-local `ident` whose `expr` type is a function type now lowers to the Lisp
name the definition already binds, and `_lower_scan_function_value` establishes
that callee the way `_lower_scan_call` establishes a called one, so it carries
the same reach to file-scope state and the compiler surface. A file-scope
function *pointer* is untouched: its type is `(* (func ...) ...)`, not
`((func ...) ...)`, so it stays a `C.gread`.

**Two rows in `etc/comptime.xlisp`**, `Func_var` and `Var_func`, both the
identity, because a Lisp lambda already is a value. They are what a `Func`
stored in a `Map` and read back needs.

### What it costs

Nothing measurable. `comptime-autodiff.x`, whose 106 compile-time functions
are the largest corpus in the repository, translates in 0.70 s before and
0.70 s after - the minimum of five interleaved pairs of the two binaries in
`builds/0` on one host. The added work is two match attempts per scanned node,
and the scan runs twice.

### Evidence

Six rows in `unittest/compiler-fixtures/comptime-lowering.x`, each printing
the compile-time answer beside the same function's run-time answer:

| row | construct |
| --- | --- |
| `func-none` | `f()`, the bare `Func_apply` spelling |
| `func-one` | `f(v)` with a `Var` argument |
| `func-two` | `f(a, b)` with an `int` and a `String` |
| `func-named` | a meta function reaching a `Func` by name |
| `func-higher` | `map`, `filter` and `foldl` as meta functions |
| `func-thunk` | a `Func` stored in a `Map` and read back |

`make build` is clean with no new warnings, `make verify-fixtures` reports 731
passed, `make verify` 924 passed, and the documentation audit passes.

### What this unblocks

- `etc/init.xlisp`'s `map`, `filter` and `foldl` are written as meta functions
  in the fixture and answer correctly, which was the shape M8 needs.
- A `Map` of thunks lowers, which is what Phase 6 gave back 149 ms for. Whether
  `ad_partial` recovers it is not measured here.
- A general `lib/var-tags.xmacro` port no longer needs `var.tag.map` and
  `var.tag.filter` rewritten as `List.map` and `List.filter`.

### Two dictionary gaps this found, not fixed here

Neither is about callable values, and each is a row in `etc/comptime.xlisp`
that no caller has yet asked for. `Var_add` - arithmetic on two `Var`s, which
a lambda over two boxed arguments writes naturally - and `List_str`, which
`%"${someList}"` needs. `x + 1` on one `Var` is unaffected, because that is an
`op` node rather than a protocol call.

## M8 - installing a compile-time function at session start

**Built.** The route is `Frontend._preload_meta_surface` in `src/frontend.x`,
called once per process from `Frontend.preload_macro_libraries` and wired at
`src/main.x`. It parses `lib/meta.x` as its own unit against the shared
session, which is the answer to the third wall below.

Both of Phase 7's walls are down, and a
third one is up that Phase 7 did not name. The route that remains is real but
it is a new entry point, and its cost is per process rather than per unit.

### Phase 7's first wall does not apply to `meta`

Phase 7 recorded that a session-start install "cannot happen during the
library load as `_ensure_lisp` is written, because `x2c.comptime.install` is
not bound until after the five libraries are evaluated". That is true of the
`$comptime()` decorator, whose install goes through the Lisp native. It is not
true of `meta`: `Compiler.install_meta_function` in `src/macros.x` calls
`_ensure_lisp` and then `Compiler.install_comptime` directly, in x2c, and
never touches the native. M1 moved the install off that path and the wall went
with it.

### Phase 7's second wall is down, and the coupling it warned about is now real

Phase 7 recorded that "the checked-in `bin/x2c` has no `etc/comptime.xlisp`
and no comptime install at all", so moving `foreach` out of Lisp would break
the bootstrap chain until a refresh landed the capability. The refresh landed
on this branch as `e4db6c78`, for Phase 5 rather than for this milestone:
`bin/x2c` is a symlink to `bin/x2c-bootstrap`, which is built from
`bootstrap/*.c`, and it now parses `meta` and carries
`bootstrap/src/comptime.c`.

Phase 7 also said this is a permanent coupling rather than a one-time
transition, and that is now the state of the tree: every future bootstrap
binary carries the comptime lowering.

### The wall Phase 7 did not name: a meta function needs the unit's types

A `meta` function that reads a table needs `Array.push` and `List.getindex`,
and a `.xmacro` gets them from the consuming unit's symbol table. Phase 5
reproduced what happens when the unit has not declared them: `lib/common.x`
reports `type ("Array") has no method push`, at line 18 and still at line 614.

`_ensure_lisp` runs for every unit, `lib/common.x` included, and a
session-start install has no unit at all. So the shipped file cannot borrow a symbol table
the way a `.xmacro` does; it has to be its own translation unit that includes
`lib/x2c.x`, parsed on a child compiler whose only output is the lowered Lisp.
That is Phase 5's route 1, "the compiler sub-translates a named `.x` at import
time", and it is the only route left.

Whether `etc/init.xlisp`'s own candidates need any of that is a separate
question and the answer may be no: `map`, `filter`, `foldl`, `caar`, `cadr`
and the rest take and return `List`, and M7 established that all three of the
function-taking ones lower and answer correctly. They still need `List`
declared to be parsed.

### What it would cost

Phase 7 measured 158 ms of install for 111 functions on top of 231 ms of parse
and type, and a trivial unit at 62 ms, most of which is the prelude. A
session-start unit pays the prelude once per process rather than per unit,
because `src/comptime.x` keeps the lowered forms for the process, so the cost
to beat is one prelude parse plus the per-session `eval` of the definitions.
Neither has been measured for this shape.

### What would settle it

One probe, on a branch: give `_ensure_lisp` a final step that parses a shipped
`etc/init.x` on a child compiler the way `_import` parses a `.xmacro`, and
measure `x2c translate` on one trivial unit and on `src/*.x`, against the same
tree without the step. If the per-process prelude is the whole cost, the
20 `defun`s in `etc/init.xlisp` that need no function argument become `meta`
and the five that take one follow. If it is per unit, this stays Lisp for the
same reason `etc/builtin-macros.xlisp` does.

`protect_x2c` in `lib/lisp.x` is unchanged and still refuses a `def` of an
`x2c.`-prefixed name once the first native is bound, so the
`etc/builtin-macros.xlisp` direction is still closed. Phase 7 declined that on
its own evidence and this milestone does not reopen it.

## The emission gap `meta` leaves in a unit

A meta function declared **in a unit** is emitted unconditionally, so one whose
every call folds is dead code a `-Wall` build would name. An **imported** one
is emitted only where a run-time call reaches it - verified: the four ported
`dedent` functions appear nowhere in the C of the one unit that imports them.

The fix is to extend that same reachability walk from imported definitions to
a unit's own, which is one mechanism reused. It is not a second keyword: a
`func`-style spelling for "compile-time only, never emitted" was considered
and rejected, because non-emission is derivable from reachability and a second
spelling would mean two ways to say "compile-time function". M6 already refuses
emission in both places for one derived property.

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
beat. M6 wrote no implementation at all: the `_sdk_*` operations already
existed, so it is a declaration file and a table of forwarding rows, and it
reuses M5's propagation rather than adding a second one.

Two lasting new mechanisms. The contextual `meta` marker exists because the
parser must know a fact before macro expansion that no macro can tell it. The
`Meta` namespace exists because a declaration is how x2c names an operation,
and it earns a second job: the namespace is what makes "compile-time only"
derivable without a keyword.

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

## The shared parent is built between units

The frozen parent session is still mandatory for any unit that opens a
compile-time session, and it is still built while the process Context and
root pool are current. It is no longer built before the first unit. A
translate request that runs its units in this process defers it: the first
unit that reaches `_ensure_lisp` raises `<lisp-late>` before it has written
anything, `_compile_file` catches that after the unit's Context has closed,
builds the parent, and translates the same unit again. A unit restarts at
most once, because the parent is settled by then, built or recorded as
unavailable. Behaviour does not depend on how many files the process was
given or on which unit needed Lisp first.

Parallel translation and every dump still preload up front: a worker
inherits what the parent process built, and a dump interleaves diagnostics
with its own stream. A unit whose diagnostics could be printed by an attempt
that is later abandoned holds them until it finishes; the error floor in
`Compiler.report_error` flushes what it collected when no printer is
installed.

A program that never opens a session no longer pays for the parent: a hello
world translates in 34 ms where it took 47 ms. A program that does opens it
about 6 ms later than it would have, which is its abandoned first parse.
