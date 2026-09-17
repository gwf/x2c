# x2c dogfooding remediation

> Status: active - Phases 1 and 2 are authorized and land with this plan.
> Phases 3 through 10 are scoped and wait on Gary. Scoped 2026-09-17 from
> five sweeps at HEAD ecdcea9 (packages and cleanup, classes, arrows and
> percent literals, core idioms, periphery idioms). Counts below are authored
> sites reproduced by those sweeps; every "identical translation" claim was
> decided by rewriting the line and diffing the generated C, not by reading.
> The six defects the sweeps reproduced are routed to
> `repository-review-2026-09-17.md`, not carried here.

## The result

The compiler and runtime adopted the current language on 2026-09-11 in
[core-system-macro-adoption](archive/core-system-macro-adoption.md); nothing
else did. Agents read the periphery and the guidance rather than the archive,
so the repository teaches an older x2c than it implements: `packages/` holds
511 `defer` statements, zero `$auto`, and no `Cleanup(T)` adoption at all; the
compiler never writes the `in` operator it implements; the book's cleanup
section teaches the pair `$scope()` replaces, four lines after telling the
reader to use `$scope`; 33 of 55 showcase examples use none of the current
features.

This campaign makes the repository an exemplar of the language it ships,
because agents reproduce what they read. Phases are ordered by how many future
authored lines each one steers per unit of delivery cost: the guidance an
agent opens on every task first, the book second, the package adoption that
unblocks users third, bulk mechanical adoption last.
[examples/programs/literate-lisp.x](../examples/programs/literate-lisp.x) is
the style reference throughout.

Two cost facts govern execution and belong in every executing session:

- **Translation-identical phases cost nothing downstream.** `in`, `->` to `.`,
  receiver calls, `=>`, and declaration grouping emit byte-identical C.
  `bootstrap-refresh` copies `builds/0/{src,lib}/*.[ch]` into `bootstrap/`, so
  those phases leave `bootstrap/` empty in the diff. The acceptance test is a
  diff of the generated C before and after, not a rebuild argument.
- **`$auto` and designated initializers change emission.** Those phases carry
  a real bootstrap refresh and a genuine stage-diff round.

## Phase 1 - the guidance an agent reads first

These files are read on every task, none is gated, and two of them contradict
each other about pointer member access.

[agents/x2c-coding-style-guide.md](../agents/x2c-coding-style-guide.md):
add the acquire-and-cleanup rule under `### Trust supported conversions` -
prefer `$auto`, `$scope()`, `$lock`, `$let` to a hand-written pair, keeping
`defer` for native releases, conditional rollbacks, consuming parameters, and
counters. Add the member-access boundary beside `### Prefer receiver chains`.
Delete the sentence under `### Literals, strings, and formatting` that keeps
`%""` for an empty String: it is disproved by probe and by
`docs/src/guide/collections.md:459`, which writes `String empty = "";`. Extend
the percent rule with the two real exceptions: keep `%{}` and `%[]` at a `Var`
or untyped destination, and keep `%{ ${...} }` for constructed entry rows. Add
the class budget under `## Representation and lifetime stay visible`. Add two
`## Review checklist` lines.

The member-access rule, stated correctly: write `.` wherever x2c parsed the
struct, including a C header x2c reads; `->` remains only for a layout x2c
never sees, a member of an anonymous aggregate, a call through a
function-pointer field whose name collides with a method, and inside a
`#define` body. Keep `(*p).field` where one `.` cannot reach through two
pointer levels.

[agents/x2c-debugging-guide.md](../agents/x2c-debugging-guide.md) `### 1.3
Pointer Access` states universal `.` and needs the same four limits.
[agents/x2c-philosophy.md](../agents/x2c-philosophy.md) pairs an inner
`Scope.retain` with a guaranteed release, which predates `$scope`, and its
exemplars should name `literate-lisp.x` and `examples/magic/system-macros.x`.
[packages/AGENTS.md](../packages/AGENTS.md) requires "`defer` beside native
acquisition", which is the rule that produced 320 hand-written defers; it must
require `protocol Cleanup(T)` for every handle wrapper that owns native
storage, explicitly not for borrowed views.
[integrate-x2c-package](../agents/skills/integrate-x2c-package/SKILL.md)
follows.

Do not change: the guide's `cadr` examples, which follow its own advice; the
existing `audit-source.sh` checks; no new gate or review step.

Verification: `tools/gate-state.py ensure doc-check`. `agents/*.md` is not
audited by `tools/check-docs.py`, so the review is the verification, and every
added claim cites the probe or file that establishes it.

## Phase 2 - the book chapters that teach superseded spellings

[idioms.md](../docs/src/guide/idioms.md) `## Put cleanup beside acquisition`
is the last place that teaches the manual pair as the idiom; rewrite it around
`$scope()` and `$auto`, keeping `defer` as the general mechanism. The same
treatment for `exceptions.md`, `memory.md`, `torch.md`, `iteration.md`,
`library/overview.md`, and `contexts-and-threads.md`. `match.md` carries 24
`Var_int` and `String_str(Var_str(...))` sites across all 11 example blocks,
in the chapter that opens by promising the reader an escape from exactly that
spelling. `language.md` states that raw pointer member access still uses `->`;
replace it with the Phase 1 boundary and say that a header x2c cannot read
keeps `->`. `wrapping-c-libraries.md` never mentions `Cleanup`, `$auto`, or
`class`, and its `Array.new()` contradicts the style guide.

Document `in`. Today it appears only as a lexing note in `language.md` and
`from-c.md` and one protocol row in `protocols.md`, while Collections and
Idioms teach `.contains`. That omission is why the compiler's own source uses
the operator zero times.

`lib/scope.x` tells readers to pair retain and release with `defer`; its
prose generates `docs/src/library/modules/scope.md`, so it changes with a
code phase rather than here.

Do not change: `memory.md`'s mechanism section, its `defer fclose(log)` C
example, and its deliberate dangling-pointer demonstration; `exceptions.md`
where `defer` itself is the subject; `collections.md`'s `SymbolSet`
membership example, because `in` does not accept a `SymbolSet` receiver
today.

Verification: `make doc-generate` first, because `doc-check` runs
`gen-llms-txt.py --check`; then `tools/gate-state.py ensure doc-check`; then
`make doc-examples` by hand for the changed chapters, since it is optional and
ungated. Use `~` hidden lines for context rather than `x2c,ignore`.

## Phase 3 - packages adopt `Cleanup(T)`

The enabling change, and the reason package users cannot write `$auto` at all
today: a consumer gets "managed initializer requires Cleanup participation",
and consumer-side adoption does not work.

Three lines per type, no call site touched, no descriptor row consumed:
`void T.cleanup(T);` and `protocol Cleanup(T);` above `#pragma private`, and
`void T.cleanup(T v) { v.free(); }` below it. Fourteen types across nine
packages, ordered by defers unlocked: UvLoop 60, CurlResponse 48, CurlEasy 33,
BlisObject 33, Regexp 31, Image 30, UvProcess 20, Database 17, Statement 16,
JsonDocument 16, CurlBatch 9, ImagePixels 4, Termbox 2, RaylibWindow 1. The
pcre2 probe rebuilt the archive and `examples/parse-log.x` with both defers
replaced by `$auto` and produced byte-identical output.

Do not change: `T T.free(T)` keeps returning its handle, so chained calls
still work. Borrowed views never adopt - JsonValue, JsonArray, JsonObject,
and JsonMember borrow the document. torch keeps its Scope-region model. Every
`free` and `close` must stay null-safe and idempotent, because cleanup now
also runs on error paths.

Verification: per package, `make -C packages/<name> test run`, plus `run-lisp`
where it exists, and `make packages-check` when the dependency cache is
present. Packages are outside `make check`, so the package test is the real
evidence.

## Phase 4 - package call sites, one package per delivery

One recipe, nine deliveries; do not batch packages into one change. 320
`defer x.free()` and `defer x.close()` become `$auto(...)`, plus 27 sites on
types that already participate (Lisp, File, Bytes, Block, Context, Array). The
29 sites spelled `Scope.retain(); { defer Scope.release(); ... }` - the
macro's own expansion, written out - become `$scope() {`, a pure deletion. 155
`{ return e; }` bodies become `=> e;`, 54 non-interpolating `%"..."` become
plain literals, 14 arrows go, and two `$let` regions land in torch.

Do not change: the ~190 native-header arrows; the ~40 raw-C releases in the
raw-API tests, which exist to exercise the C API; the ~10 conditional
construction rollbacks in libcurl; six struct-field releases in the libuv
tests where cleanup must observe the field rather than a local; consuming
parameters and counters;
`packages/libuv/tests/test-raw-api.x`, whose subject is the raw C surface and
which holds 71 of the removable arrows; and
`packages/termbox2/examples/incident-filter.x`, whose dead null check must go
first because `File.cleanup` is `fclose`.

The 60 head-of-function retain and release regions are excluded: converting
them re-indents the whole function body, because `$scope` decorates a
statement. See the open decisions.

## Phase 5 - the exemplar examples and the slides that own them

`examples/tours/language.x` is the flagship executable tour and uses none of
`$scope`, `$auto`, `in`, `is`, `=>`, or `class`; the probe reproduces its
expected stdout in 38 lines instead of 53. `examples/power/scopes.x` and its
site slide are the public scope lesson and hold four hand-written pairs; keep
one as the primitive being taught and name `$scope()` in the prose.
`examples/programs/lisp.x` sits beside `literate-lisp.x` and reads a
generation older. Smaller: `magic/lambdas.x`'s five `Var_integer` wrappers,
`love/basic-literals.x`'s class-style calls, `magic/operators.x`'s membership
tests, 15 `$auto` sites, and the first `$lock` a reader meets in
`power/shared-threads.x`. Re-sync the three provably stale package slides
against the sources they excerpt.

`examples/magic/protocols.x` becomes three heap classes: 66 authored lines to
32 with identical stdout, the one class conversion in the repository that
pays. It spends three of the 31 descriptor rows in a program that spends none.

Do not change: `examples/shootout/**/ported.x`, whose contract is the C
reference's representation; `tiny-lisp-min.x`; `love/methods.x` and
`power/indexing.x`, which exist to teach hand-written constructors;
`literate-lisp.x` itself; and `power/collection-indexing.x`, whose adjacent
declarations are a per-line catalog.

For gallery entries the slide is the owner: edit the slide, then run
`python3 tools/check-gallery-examples.py --update`.

## Phase 6 - `in` in src and lib

The largest dogfooding gap in the core: zero uses against 142 `.contains(`
calls, while `literate-lisp.x` uses it ten times. Convert the ~95 positive
membership tests on Map, List, Array, and String receivers. Probe-verified:
`x in m` emits exactly `Map_contains(m, x)`, including for typed families.

Do not change: the 47 negated sites, because there is no `not in` spelling;
the 17 `SymbolSet` receivers, which `in` rejects; the 10 `kind() ==` sites,
which compare tag families.

Verification: `make build`, then diff the generated C under `builds/0/src` and
`builds/0/lib` against a copy taken before the edit. The diff must be empty.

## Phase 7 - arrows and percent literals in src, lib, tools, unittest

76 arrows after exclusions: `lib/var.x` 22, `lib/iter.x` 5, `lib/lisp.x` 1,
`lib/map-generics.xmacro` 2 (the only macro template with a hole-typed
receiver, verified through its instantiation), `src/expressions.x` and
`src/transform.x` 8, `tools/x2c-graph` 5, `unittest` 17. About 40 percent
sites, the better half of which is under-use: eight `%"$buffer"` conversions
in `src/` become the bare identifier.

Do not change: the 190 native-header arrows; `#define` bodies; the
function-pointer field whose name is also a method; anonymous-aggregate
members, which are a compiler defect; all 18 `(*p).field` spellings; the 31
arrows and ~128 percent strings in `unittest/compiler-fixtures/`, whose
spelling is the subject under test; `===` identity comparisons; `Var.new`
raw payloads; interpolating and multi-line percent strings; and
`String.new("literal")`, which allocates where a cached literal does not.

## Phase 8 - initializers, receivers, and expression bodies

`src/` contains one designated initializer in 33,391 lines, which is why
agents never write one. Convert the 26 allocate-then-assign sites to compound
literals with designated initializers, three `memset` calls on plain structs
to `x = (T) {0}`, 15 `Type.method(x)` calls whose receiver already selects the
callable, three `List_var` ternary arms, six single-`return` brace bodies to
`=>`, two destructuring sites, and the 52 C-style `Block_*`, `Bytes_*`, and
`Scope_*` calls in the generics macros, which already mix both spellings.

Do not change: initializer expressions whose evaluation order C leaves
unspecified; structs embedding large arrays, where a compound-literal copy is
not free; union members, where a designated initializer does not guarantee
zero in the unnamed bytes; the zeroing that must precede fallible
initialization; and manual walks that need the cursor.

Deliver the generics-macro change separately: those 52 sites expand into every
typed Array and Map.

## Phase 9 - declaration grouping, opportunistically

559 adjacent groups would form one row under 80 columns, removing about 611
lines, and the style guide already requires it. This is enforcement, not a new
rule, but 267 rows across eight files is the largest reviewer burden in the
campaign for the smallest per-site gain. It becomes a lint rule and
`clean-x2c-source` work when a file is edited for another reason, rather than
a delivery of its own.

## Phase 10 - showcase coverage for features with none

`delegate`, `Self`, `with`, reference parameters, and destructuring assignment
have zero showcase coverage; `$let`, `$lock`, and class-with-methods live only
in `magic/system-macros.x`, so the gallery's answer to "how do I manage a
lifetime?" is still retain plus `defer`. One or two new examples cover the
five uncovered features, and `class` and `$auto` move into at least one
ordinary example. Manifest rows and expected stdout only; no gallery slides,
which keeps this out of a gallery redesign. `make examples` stays optional.

## Excluded from the campaign

- **Class conversions in src and lib.**
  [core-system-macro-adoption](archive/core-system-macro-adoption.md)
  deferred them as policy and the measurement agrees: a record or heap class
  spends one of 31 shared descriptor rows whether or not it is ever boxed, and
  the compiler's bootstrap already spends about 20. Across 944 authored
  typedefs only `examples/magic/protocols.x` clearly pays.
- **Error-path cleanup changes in src and lib**, deferred by the same archive.
  Teaching examples in Phase 5 do adopt them, which is the one place this
  campaign crosses that line deliberately.
- **The 287 `$test.scoped()` sites.** The macro is already the one-token
  region; `$scope()` would re-indent 287 test bodies for nothing.
- **A content check for `source` entries in
  `tools/check-gallery-examples.py`.** It would have caught the three stale
  slides, but a recurring check needs Gary's approval and an equal-cost
  removal under the process ceiling. Phase 5 fixes the drift by hand.
- **`delegate Sym sym` in `struct Compiler`** (456 call sites): it would hide
  which owner holds symbol state, and a future name collision would resolve
  silently.

## Open decisions

1. **May `$scope` decorate a function definition?** Sixty package regions and
   most example regions are whole-function, and converting them today
   re-indents the entire body. Logger's private `synchronized` decorator is
   the precedent for a function-target decorator. This is language surface and
   must not be slipped into a cleanup pass. It decides Phase 4's scope.
2. **Should `SymbolSet` participate in `in`?** The style guide recommends
   `SymbolSet` for a closed vocabulary and `in` for membership, and today they
   do not compose: `in` resolves through `Var(T)`'s `contains` and `SymbolSet`
   adopts no protocol. It decides 17 sites and whether `collections.md` can
   change. A `not in` spelling is a separate question and is not proposed.

## Plan review

**Facts established elsewhere and not rechecked.** Every count and every
identical-translation claim comes from the five sweeps, which decided them
mechanically: the arrow sweep rebuilt each of 374 candidate lines and diffed
the generated C individually rather than applying a rule. This plan re-derives
none of them. The `Cleanup(T)` recipe is proven end to end on pcre2; no phase
re-verifies that `$auto` frees. `bootstrap-refresh` copies the generated C, so
the empty-diff proof is the same fact the gate establishes later, obtained
earlier and more cheaply.

**Deletion and reuse.** The campaign is almost entirely deletion: 320 defers,
29 hand-expanded regions, 155 brace bodies, 178 arrows, 305 percent sigils,
and 15 lines from the flagship tour. The additions are 42 lines of `Cleanup`
adoption across nine packages, the corrected rules, and the Phase 10 examples.
No new helper, representation, traversal, cache, or macro is proposed;
`$auto`, `$scope`, `$lock`, `$let`, `in`, `class`, and `Cleanup(T)` are
shipped mechanisms being used.

**Idiomatic x2c.** The target spelling in every phase is the one
`literate-lisp.x` already writes, and the acceptance test for most phases is
that the compiler emits the same C, which is the strongest available statement
that a change is spelling rather than machinery. The one place this could
import a framework is package lifetime management, and it does not:
`Cleanup(T)` is two declarations and a one-line body, torch keeps its region
model, and borrowed views adopt nothing.

**Validators, diagnostics, and negative fixtures.** This campaign proposes
none, and adds no gate, test requirement, commit step, or planning step.
`make examples` and `make doc-examples` stay optional and manual. The
diagnostics the sweeps found missing are routed to
[repository-review-2026-09-17](repository-review-2026-09-17.md), where each
protects wrong output or a crash rather than rejecting legal syntax earlier.
