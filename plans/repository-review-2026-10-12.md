# Repository review before the cleanup phase, 2026-10-12

> Status: active - review record at `origin/dev` `2ec6ea71`, 2026-10-12.
> Every finding below was reproduced at that commit in this worktree unless a
> row says "by reading". Gary decided the rows on 2026-10-12; the
> [decisions](#decisions-recorded-2026-10-12) section records them, and the
> execution log at the end records what landed.

## Decisions recorded 2026-10-12

1. **Numeric comparisons.** `==`, `!=`, `<`, `<=`, `>`, and `>=` on two
   numeric Vars behave as the same comparison between their native values in
   C, through the arithmetic conversion ladder `Var.binary` already uses, so
   mixed signedness and NaN follow C. `===` on numbers requires the same type
   and the same bits, so `NaN === NaN` stays true and `+0.0 === -0.0` stays
   false. Map and Pool keys, `Var.hash`, `Var.compare` and sorting are
   unchanged; value classes keep identity for `===`; native static operands
   are unchanged.
2. **Indices are 32-bit `int`.** The book states it. No compiler or runtime
   change; a wider value is outside the supported domain.
3. **Non-List match.** A Var subject whose tag is not `<list>` matches no
   List arm and reaches `default`. `Null` and `void` are not Lists. The owner
   is the match component's subject read.
4. **Var to String.** An implicit String destination calls `.str()`, which
   already returns a String-tagged Var's String itself and renders every other
   tag. An explicit `.string()` raises when the Var is not a String instead of
   returning NULL. The unnecessary-conversion lint stops flagging `.string()`
   at a String destination. Compiler and runtime sites that read the old NULL
   as "not a String" become `is String` tests.
5. **Component dispatch.** Each shipped rule binds to its registered function;
   component macros and helpers are private to the prelude, so a program
   definition of the same name is a separate definition.
6. **A `case` or `default` label that enters a protected cleanup region** is
   rejected at compile time with the `goto` diagnostic family.
7. **Self-meta.** A function rule rewrites the program's definitions; the copy
   the compiler runs is compiled as written. The book sentence at
   `docs/src/guide/meta-functions.md:96` says so. No code change.
8. **SDK.** `Code.register_after_initialization` stays: it is the only hook on
   every initialized declaration of a type, `$rewrite` rejects ordinary
   declaration patterns, and the optional spike runner still passes all 17
   cases. One spike case becomes a compiler fixture. `x2c_meta_definition_hashes`
   stays.
9. **Seams.** Both components place code through `x2c_place`; `add_early`,
   `needs_exception`, `localinit`, and `lower_defer_region` stay
   kernel-internal; the linked prelude stays, and the generated
   `src/linked-meta.x` is excluded from lint censuses and module maps.
10. **AR-3** is reworded: a new lowering is a shipped component on the two
    primitives, and the driver gains no ordered pass list and no struct IR.
11. String `switch` and typed `_Alignof` are deferred past the cleanup phase.
    The 114 remote branches merged into dev are deleted; the 14 unmerged stay.
    `.context/language-components/performance.json` is untracked.

Delivery: direct to dev through `tools/land-dev`, one gate per batch, in the
order of the recommended order below.

## Result

The tree is healthy by its own checks and the component campaign left almost
no dead code. The baseline at `2ec6ea71`: `make build-safe`, `make verify`
(948 unit tests, 1171 compiler fixtures, probes), `make doc-check`,
`make examples` (60), and the seven `tools/test-*.py` suites all pass on a
clean tree. The lint census reports 0 violations and 2,274 candidates.

What is not stable yet falls into four groups:

1. Four reproduced defects in shipped behavior, two of them in the mechanism
   the components stand on (section A).
2. Recorded decisions that change language behavior and are not implemented
   (section B). A cleanup phase that forbids functionality changes must land
   them first or defer them explicitly.
3. Design seams the component campaign left half-collapsed (section C). Each
   needs a "keep" or "finish" decision so cleanup does not rewrite them twice.
4. Organization and naming facts for the cleanup backlog (section D), plus
   documentation drift (E) and repository hygiene (F).

## Baseline and coverage

Scope: compiler, runtime, build and tooling, tests, examples, the book and
agent guidance, plans, branches, and release state. Recent work guided the
discovery: 296 commits since the components foundation `ccf0db26`
(2026-10-09), of which 92 are bootstrap or generated refreshes.

Six bounded read-only reviewers covered kernel residue, the plan's open
rule-driver defects, module blocks with acquired cleanup, the undelivered
semantic decisions, a naming census, and documentation drift. Each claim in
this record was rerun or reread by the review session before it was kept.

Not examined: `site/`, `packages/` source, `commands/` beyond one test,
editor-adapter positions for replayed module effects, performance under an
idle host, the 190 Var-subject matches and the implicit String reads in the
compiler one by one, and unreachable branches inside live functions.

## A. Reproduced defects

Ranked by consequence. Probe programs are under the session scratch directory
`modules-cleanup/`, `rule-defects/`, and `semantics/`; each row names the
probe and the observed output.

| # | Defect | Evidence | Consequence |
| --- | --- | --- | --- |
| A1 | A `return` inside a `defer` finalizer or a source `finally` skips `x2c_exception_leave`, so the next `raise` inside any `try` hangs. | `rule-defects/extra/defer-return-frame.x` and `finally-return-frame.x`: `returns 4 / caught 99 / returns -1`, then killed by the CPU limit (status 152). Generated C: `if(x2c_exception_claim(&f)){ if(n < 0) return -1; } x2c_exception_leave(&f);`. The fixture `rewrite-try-defer-landing` never raises after such a return. | Any program with a returning finalizer corrupts the exception stack. Highest priority. |
| A2 | Shipped component translators are dispatched by global name. A program `meta` function with a shipped translator's name replaces it or makes its form lower silently. | `rule-defects/b/b2-meta-interpolation-same-signature.x` defines `meta Code interpolation(Code) => $!String{ String.new("program's") }`; `%"n is $n"` prints `program's` with no diagnostic. `d/d-access-read.x` defines a declining `access_read`; the C holds `Var_integer(getindex items 1)`. The components define 26 macros, 30 public and 95 static meta functions that a program can collide with; `$collection_store` also shadows a program call of that name. | The component mechanism is not hygienic; 12 language features can be hijacked by an ordinary name. Fix: dispatch rules by their bound function and keep component names private. |
| A3 | A replayed compile-time effect from a module member reports the module's entry file with a line counted in the spliced text; when the including unit has its own block the column is nonsense and `Compiler._own_line_start` scans a buffer the position does not belong to. | `modules-cleanup/p01b-lisp-effect/mod`: translating `user.x` reports `lib.x:12:7`; translating `lib.x` reports the correct `lib/defs.x:10:7`. `p01c-includer-module`: `lib.x:12:200` with an empty context line; column = 238 - 39 + 1, the member position minus the includer's length. | The plan's recorded module follow-up, confirmed open; the 2026-10-12 column repair in `src/diagnostics.x` added a second coordinate path that mis-fires here. |
| A4 | Module member paths are checked by spelling, not by their resolved location. | `modules-cleanup/p02-paths`: `entry/sub/../member.x` is rejected as "outside"; `entry/link.x -> ../../outside/secret.x` and a symlinked directory escape are accepted and the depfile lists the outside file; `cyc/m -> .` splices the member about 33 times until the OS refuses the path. | The plan's recorded containment follow-up, confirmed open. A resolved-containment check alone will not stop the symlink cycle; reject a canonical member path already being spliced. |
| A5 | A `case` label that enters a block after a `defer` registration compiles and aborts at run time with `cleanup chain imbalance`; a `goto` into the same region is rejected at compile time. | `modules-cleanup/p12-switch-defer/probe.x` with argument `1`: `Fatal: uncaught exception cleanup chain imbalance`, exit 1. `docs/src/guide/from-c.md:321` says jumping into a protected region is rejected. | Pre-existing, not from the recent merges. Fix: apply `Walk._goto_stop` (src/cleanup.x:582) to `case` and `default` labels. |
| A6 | A transform-time rule that declares a parser-bound name leaks it to later resolution in another function. | `rule-defects/a/a-leak.x`: generated `static int second(void){ return leaked; }` where `leaked` is a block local of `first`; the control without the rule fails to resolve the name. | The plan's open item, confirmed. Needs a user rule to trigger. |
| A7 | Function-entry placement from inside a finalizer lands in the compiler-written `_x2c_defer_cleanup_N`, and a placement made by code that was itself placed at function entry finds no frame. | `rule-defects/c/c1-defer-entry.x` prints `enter _x2c_defer_cleanup_0`; `c/c2-place-again.x` fails with `code placed at function entry needs an enclosing function` at end of file. | The plan's open item, confirmed. User rules only. |
| A8 | A program function rule rewrites the runtime form of a `meta` function but not the copy the compiler runs. | `rule-defects/e/e5-compile-time-copy.x`: `runtime poly(7) 16, compile-time $poly(7) 8`. The book says both forms come from the same body. | The recorded "self-meta discrepancy" in its reproducible form. Every other offering rule matched the book: definitions with a runtime form are offered, compile-time-only ones are not, in every position and across units. |
| A9 | `Res r = $auto($auto(acquire(1)));` is accepted and releases twice; `Res b = $auto(a);` on an already managed value does the same. | `modules-cleanup/p15-rejections/nested-auto`: `release 1`, `release 0`, abort 134; ASan reports heap-use-after-free. | Follows from the documented semantics; a rejection of a nested or duplicate `$auto` would close it. |
| A10 | Casting a C literal to `String` and indexing it reads a String header that does not exist. | `semantics/cast/cast.x`: `((String) "abc")[10]` emits `String_getindex(((String) "abc"), 10)`; the run raised `<bad-arg>` with `length -1` from `x2c_normalize_index`. A canonical `String s = "abc"` returns -1 as documented. | Pre-existing, undocumented form. The cast bypasses the literal promotion the compiler performs for plain assignment. |
| A11 | `Compiler.borrow_diagnostics` (src/compiler.x:2642) and `Sym.resolve_base_type` (src/symbols.x:1009) have no callers. | `git grep -n -w` over the tree without `bootstrap/` and `plans/archive` finds only the definitions, the generated API pages, and prose. Last callers removed in `a5cd78da` and `a1feadd9`. | Dead public surface; delete and regenerate the API reference. |
| A12 | `commands/repl/tests/api-check.x:114` builds the `early` carrier effect that `ed35a035` deleted. By reading: `_code_effects` takes its default arm and raises `malformed` under recovery, so the test's `catch` fires before the `cleanup` effect and three of its four leak checks pass without testing anything. | `grep '(early ' src/macros.x` finds no producer or consumer. Not rerun. | Drop the `early` row and recheck the three assertions. |

Also reproduced but working as documented: acquired-value cleanup releases
exactly once across loop reassignment, conditional early return, lambda
bodies, `defer` in the same block, nested blocks, NULL, and a raising second
initializer (`modules-cleanup/p10-cleanup`); module statics are shared by two
includers; nested blocks and batch replay report correct locations; the
`dstrdecl` double application, the `$tried` rule seeing defer landings, and
function rules seeing compiler-written definitions are fixed as the plan
records; a macro-built `with` (macro body and `$!{}` quotation) behaves like
the handwritten form (`with-probe/with-macro.x` prints `3 4` and `7 8`).

## B. Decisions recorded but not implemented

These change observable behavior. Each row gives current behavior at
`2ec6ea71`, the owners, and the size, from `semantics/` probes.

| Decision | Current behavior | Owners and dependents | Size |
| --- | --- | --- | --- |
| Numeric `==` by C rules; value `===` needs equal type | `3 == 3L` is false; equality requires the same tag; two boxes of `3L` give `== 1`, `=== 0`. The Var hash is per tag: keys `3`, `3L`, `3.0`, `3.0f`, `(char) 3`, `3u` make six Map entries and `{3: x}[3L]` is void. `sort` orders equal values by type rank. | `Compiler._comparison` (src/transform.x:1063); `Var.equal`, `Var.same`, `Var.compare`, `Var.hash` (lib/dispatch.x:329-514); `lib/var.x:1086-1228`; `lib/varops.x:181-209`. Dependents: Map and Pool key equality (lib/map-generics.x:16-32), `List.equal` and `List.hash` under pool interning (lib/list.x:109-130, lib/pool.x), `Array` sorting, `Iter` min and max, `lisp_eq`. | Large. C equality is not transitive (`-1 == 4294967295u`, `-1 == ULONG_MAX`, `4294967295u != ULONG_MAX`), so no hash fits it; NaN and signed zero change; sorting must keep a total order. Six assertions in `unittest/test-var.x:570-579` and two fixtures assert the old behavior. A Map key policy is unavoidable. |
| Wide indices never wrap | `a[4294967297L]` reads, writes, and updates element 1 for Array, List, String, and Var receivers; `a[2^31:]` returns the whole Array because the bound narrows to the `INT_MIN` omitted-bound marker; `a[::2^32]` raises `<bad-arg>`. Map keys and native arrays are correct. | Narrowing happens at `int` parameters and in the generated Var adapters (`src/component-protocols.x:47-62`); shared normalizers take `int` (lib/common.x:867, 887); `src/component-access.x:51-217`; the slice marker at src/transform.x:430. `List.get` (lib/list.x:495-502) already rejects a non-`int` index. | One conversion owner plus the slice marker collision; two fixture C phases. |
| Non-List match rejects its input | A Map, String, number, Array, or Symbol subject matches `case %():` and binds an empty `*rest`; fixed patterns fall to `default`. | `src/component-match.x:378` emits `Var_list(value)`, which returns NULL for any other tag. `_match_element` and `lib/lisp-init.x:115-119` already reject non-Lists. | One function; two fixture C phases. Guide wording at `docs/src/guide/match.md:264-268`. |
| Implicit Var to String calls `.str()` | `String s = v` emits `Var_string(v)`, NULL for every non-String payload, with no error; `.string()` emits the same call. | `_read_var` and `_var_exact_reader` (src/expressions.x:3463-3519); `Var.string` (lib/common.x:668); `Var.str` (lib/dispatch.x:74-89). Dependents: the unnecessary-conversion lint (src/expressions.x:3066-3099), NULL used as a tag test in `Var.hash` and Map key equality, 32 adapter call sites that must stay exact. | Medium. Three fixtures change; `docs/src/guide/values.md:131-146` prints `text=0` under the output check. |

Also recorded and open: the self-meta discrepancy (A8); String `switch`
(`plans/string-switch.md`, a feature); typed `_Alignof` with the scalar
generator cleanup; lint phase 8; and the C on-ramp landing examples, which
are documentation. The constructed `with` decision is already satisfied in
both documented forms.

## C. Design seams to settle before freezing

1. **Rule dispatch by name (A2).** The driver finds a component's translator
   by its global name, and a program definition wins. The repair is a driver
   change: bind the rule to its function at registration. Decide this before
   any cleanup touches `src/macros.x` lines 2700-3060.
2. **Two ways to place code.** The protocol component calls `x2c_place`
   (src/component-protocols.x:128-191); the lambda component returns
   `(place ...)` rows in its carrier (src/component-lambdas.x:312, 468,
   516-518), handled at src/macros.x:4960. Pick one.
3. **Private placement spellings the design said would collapse.**
   `add_early` keeps 12 callers (callables 7, cleanup 2, initializers 1,
   protocol 2) and no component uses it; `needs_exception` is a private flag
   with no placement; `localinit` stays by decision; `lower_defer_region`
   runs the design in reverse, because `x2c_place(%(block-exit))` places a
   `defer`. Decide "kernel-internal, keep" or "finish the collapse".
4. **Facts spelled in both kernel and component.** printf family table
   (src/expressions.x:20-22, 3120-3145, read only by the `.str()` warning;
   src/component-printf.x:172-206); compound-to-binary operator mapping
   (src/operator-ledger.x:11-68; src/component-operators.x:50-56;
   src/component-access.x:11-30, 153-176; the kernel maps `+=` to `+` and
   back at src/transform.x:1088 and 1131 before the component maps it
   again); update-helper call shape (src/transform.x:1215-1221,
   src/cleanup.x:820-838; src/component-operators.x:64-135); match slot
   names (src/compiler.x:2598-2614, src/parse.x:3803-3809;
   src/component-match.x:114-125, 244-251); the `Func` bridge convention
   (src/callables.x:254-769; src/component-lambdas.x:322-481), where the
   kernel hashes `c.filename` and the component's unit path uses
   `display_path`; the duplicate "provided by multiple imported packages"
   report. One owner each.
5. **Two SDK vocabularies.** `lib/meta.x` declares 19 `Code`, 20 `Type`,
   and 12 `x2c_` operations, 3 Lisp-only `x2c.literal.*` operations, and 3
   snake_case helpers (`type_base_suffix` is called by component-delegate.x:21
   although `Type.base_type` wraps it). `Code.register_after_initialization`
   and its `(decl init)` rule family have no user outside `experiments/`;
   `x2c_meta_definition_hashes` has one test user; `Type.members` has only
   test users. Components pass a NULL node in 16 of 18 `x2c_diagnostic_*_at`
   calls only to choose a category. Public SDK removals are Gary's call.
6. **Linked prelude.** The components reach the compiler as C string
   literals in the generated `src/linked-meta.x` (2,251 lines, "do not
   edit"); the plan still lists "the linked prelude's future" as open. Decide
   to keep it, and exclude the file from lint censuses and the module maps.
7. **Module coordinate mapping.** The textual splice pushes byte-position
   mapping into the diagnostics writer: `_write_heading` and
   `token_location` now carry `_own_line_start`, a raw `char *` scan beside
   the marker-based path. A3 shows the two paths disagreeing. One owner for
   "which file, line, and column holds this byte".
8. **Code standard AR-3** (agents/x2c-code-standard.md:913-916) says "fold a
   new lowering step into the driver", which contradicts the component model
   in agents/lowering-with-macros.md:8-10. A rule change, Gary's decision.

## D. Organization and naming facts for the cleanup backlog

Counts come from the naming census over 141 hand-authored files (64 `src/`,
77 `lib/` without `lib/x2c.x`), the per-file lint census in
`debug/lint-census.log`, and spot checks.

- **File names.** 52 hyphenated, 1 underscore (`lib/error_init.x`, the
  unit-initializer home for `Error.initialize`), 6 fused (`varconvert`,
  `varops`, `symbolset`, `clibc`, `cmath`, `sourceview`), so Var files have
  three spellings. Suffixes carry several meanings: `-reports.x` and
  `-report-macros.x` for split diagnostics; `-macros.x` and `-errors.x` for
  error causes; `-ledger.x` for a ledger (`operator-ledger`) and for a
  projection (`var-ledger`, `type-ledger`) while the tag ledger is
  `var-tags.x`; `-init.x` for standard natives, first-use statics, and
  `error_init`. `lambdas.x`/`component-lambdas.x`, `literals.x`/
  `component-literals.x`, and `protocol.x`/`component-protocols.x` do not say
  which file parses and which lowers. `cleanup.x` and `type.x` exist in both
  trees; `lib/lib.x`, `lib/common.x`, and `src/utils.x` do not name a subject.
- **Headers (FI-2).** 9 files miss the `/*  name.x -- purpose` first line
  (header after `#pragma once` in 7; no form in `lib/rewrite.x` and
  `src/component-access.x`). Copyright lines: 36 files say 2025, 61 say
  2026, 45 have none, including all 12 components. 30 headers carry a
  function inventory.
- **Section labels (FI-5).** 47 files have none, 12 of them over 150 lines.
  The diagnostics section has five spellings across the compiler. 8 rulers in
  `lib/var-tags.x`.
- **Function naming.** 1,628 `static _snake`, 1,607 `static Type._step`,
  1,250 public `Type.method`, 477 `static Type.step` without underscore (470
  on file-private records, 5 on public types), 236 public free functions
  (154 module-prefixed), 88 `x2c_*` (12 SDK, 10 with only runtime callers,
  all on the published C API page), 6 `Type_method`, 17 non-static `_snake`.
  Eight files mix `Owner.step` and `Owner._step` on one owner. Nine records
  carry a leading underscore.
- **Macro families.** 756 macros, 672 dotted under 30 prefixes (`$report`
  404 in 31 files). 47 one-member family paths. `$error.apply.arity` is
  defined publicly in lib/func-errors.x:13 and again as a static with
  different parameters in lib/lisp.x:142. Reason text lives in both
  `$reason.*` and `$region.reason.*`; `src/callables.x` has three report
  families. `expressions-reports.x` and `parse-report-macros.x` sit away
  from their only callers.
- **Records.** `SymTxn` (src/compiler.x:277) is used in `symbols.x`;
  `Ancestor` (src/compiler.x:97) in `parse.x`; neither is embedded in
  `Compiler`. `MacroPos` and `DiagnosticsHold` have fields read in one
  function.
- **File size (FI-1).** 21 files over 1,200 lines, 10 over 1,500; 28 under
  100. Split boundaries by crossing helpers: `src/compiler.x` clean,
  `src/expressions.x` nearly (grammar 36-929 against resolution), `parse.x`
  partial, `protocol.x` one-way (adapter generation to registry lifecycle,
  19/0), `collect.x` and `macros.x` none visible.
- **Reading order (FI-4).** 33% of 6,496 intra-file static calls go to a
  helper defined above the caller; 11 types are defined after first use;
  `lib/path.x` and `lib/process.x` put helpers above their public callers;
  `src/component-try.x` is bottom-up by the linked-copy constraint, which 8
  of 12 component headers repeat.
- **Comments.** `src/generate.x:39` names `transform_ast`, now
  `_transform_ast` and `Compiler.transform`. 37 `prohibited-prose` hits (27
  "rather than"). No stale mechanism names remain in source comments.
- **Lint census.** 2,274 candidates, 0 violations, in 120 files; the ten
  largest rules are `silent-shape-guard` 391, `short-control-flow` 277,
  `internal-type` 259, `long-dispatch-arm` 238, `literal-report-error` 162,
  `runtime-forward-declaration` 161, `long-name` 157, `struct-copy` 125,
  `horizontal-form` 68, `repeated-routes` 57. Top files: `src/macros.x` 184,
  `lib/common.x` 162 (154 forward declarations), `src/parse.x` 153,
  `src/expressions.x` 145. 51 findings are in the generated
  `src/linked-meta.x`. `long-section` counts only lower-case `//` labels;
  with block labels counted, 3 of its 20 findings stay over 400 lines.

## E. Documentation drift

Agent guidance:

| Location | Stale statement | Current truth |
| --- | --- | --- |
| agents/x2c-code-organization-guide.md:12-27, 36-63 | compiler map without any `component-*.x`; runtime table without 22 lib files (args, array-generics, cleanup, datum, diff, digest, error-macros, error-private, func-errors, integer-ops, json, list-selectors, map-generics, native-scalar-types, private-keywords, regex, rewrite, scripting, system-macros, type, var-adapters, var-tags) | 12 components lower most language features; `callables.x` lowers only `Func` conversions |
| agents/x2c-code-standard.md:544-548 | `src/cleanup.x` calls `builtin_try_cleanup_placement` | deleted in `c62b36c1` |
| agents/x2c-code-standard.md:886-889 (LI-3) | name SDK operations `x2c.<noun>.<verb>` | `Code.member` and `Type.member` per language.md:2006-2008 |
| agents/x2c-code-standard.md:903-904 (AR-1), 913-916 (AR-3) | lowering lives in `transform.x`, `callables.x`, `cleanup.x`; fold new lowerings into the driver | shipped `component-*.x` rules; see C8 |
| agents/x2c-philosophy.md:106, 628, 777 | printf transform; `src/transform.x` owns the volatile rule | `src/component-printf.x`; `src/cleanup.x:749-830` |
| agents/lowering-with-macros.md:112, 373, 390 | `%(code-value "lowered" ...)` literal; `Walk._catch_clause`; `_builtin_registration` | `Code.lowered(...)` (src/component-try.x:260); `_try_catch_clause`; deleted in `06481f63` |
| agents/adapters-macros-decorators.md:140, 209, 567-569 | `lib/varops.x:55-68`, `:25`; "add constructors" | `$native.update` at lib/varops.x:94; the SDK declares no constructors |
| agents/replacing-manual-ast-walks-with-match.md:276 | `src/type.x:78,95` | `src/ast.x:138,157` |
| agents/quick-start.md:283 | lambdas in `src/literals.x` | `src/lambdas.x` and `src/component-lambdas.x` |
| agents/x2c-debugging-guide.md:126 | field resolution in `src/compiler.x` | `Sym.lookup_field`, src/symbols.x:1201 |
| agents/x2c-development-guide.md:25-34 | `make build` runs the edit | a plain `make build` after editing a shipped component leaves a degraded compiler until bootstrap refresh (plan log 2026-10-10) |
| agents/skills/improve-x2c-agent-process/SKILL.md:32 | `plans/agent-failures.md` | created on first capture by `tools/agent-failure.py` |
| commands/graph/README.md:201-202 | `make datasets` | no such target; `x2c graph datasets OUTPUT ...` |

The book:

| Location | Stale statement | Current truth |
| --- | --- | --- |
| docs/src/internals/implementation-map.md:107-112, 131, 175, 268, 279, 298-303, 343-344 | delegate, `is`, counted construction, raise, and "most extensions" lowered by `transform.x` or `emit.x`; `lib/meta.x` as syntax builders | `src/component-delegate.x`, parser-emitted `Var_is`, `src/component-literals.x:25,44`, `src/component-raise.x`, the components; `Code`/`Type` methods. No printf section. |
| docs/src/guide/match.md:276-280 | direct checks only for a fixed symbol with unique `?` binders | literals, nested Lists, and a final `*` are tested in place |
| src/protocol.x:1-8, 2464 (feeds compiler-api/protocol.md) | "generates the adapters" | presents `conform` forms; `component-protocols.x` writes the adapters |
| docs/src/internals/architecture.md:754-894 | 10 of 12 components | no paragraph for literals or interpolation |

Plans with stale references: `plans/x2c-lint-and-format.md` (tools moved to
`commands/`), `plans/meta-followups.md` (`--system-headers`,
`etc/runtime-objects.sh`), `plans/macro-sdk-and-system-macros.md` and
`plans/overengineering-candidates.md` (`src/comptime.x` and deleted queries),
`plans/review-remediation-language-ledger-2026-10-11.md:107`
(`plans/module-blocks.md` is archived). Section B's book pages are listed in
`docs-drift/` by decision.

Verified current: the root `AGENTS.md` repo map, the module catalog, the
syntax data (`module-block`, `raise-statement`, destructuring, percent
strings; `syntax-spec check` reports 0 stale), every `make` target and `x2c`
subcommand outside plans, the skills, and the generated API pages for the 12
components.

## F. Repository and process hygiene

- `origin` has 131 branches; 114 are merged into `dev`. Of the 14 unmerged,
  `codex/nested-modules-spike` (236 commits, the rejected module design),
  `gwf/hooks-spike` (50), and `gwf/language-components` (5, superseded) are
  the largest.
- `main` is at `bc0de7d9` (2026-10-02), 3,547 commits behind `dev`. The
  release plan reserves promotion for an explicit selection.
- Five commits on 2026-10-12 (`e7b2be43`, `9db47909`, `5a20cb8c`,
  `2557fd72`, `71e933b0`) carry `Co-Authored-By` and `Claude-Session`
  trailers and the author `Claude <noreply@anthropic.com>`, from a web
  session that did not load the attribution rule. History is not rewritten;
  the rule needs to reach that session type.
- `.context/language-components/performance.json` is tracked inside the
  ignored `.context/` directory.
- 92 of the 296 commits since the foundation are refresh commits. A cleanup
  phase of pure moves can batch refreshes per publication.
- All GitHub workflows are `workflow_dispatch`; the publication gate is local
  by design.
- The nightly performance history under the main checkout shows the
  sequential build CPU seconds at 35.4 (Oct 7), 40.0 (Oct 9), and 44.7 (Oct
  10 and 11) on clean nights, a 26% climb against a 1.6% growth in authored
  lines, before the Oct 12 row doubled every metric including runtime
  microbenchmarks and the shootout ratio, the same pattern as Oct 2 and Oct
  6. The doubled row is a host artifact; the climb is unexplained and was not
  re-measured here because the host was busy.

## Refuted or unresolved

- The plan's "13 components" is 12.
- `_cell_declaration` no longer exists; `plans/compiler-kernel-minimal.md:184`
  and `:413` still name it.
- No `Compiler` field is unread; the plan's statement stands.
- A2's collision was also tried with a program macro `$collection_store`
  and a program `meta static _collection_family`: neither breaks anything.
- The out-of-bounds read in A3 is inferred from `_own_line_start`; ASan did
  not flag it, likely because the text sits inside a larger allocation.
- Whether the bridge-name hash in C4 differs between checkouts was not
  established; `bootstrap/` holds no absolute path.
- A12 rests on reading, not a run.

## Recommended order

1. A1, then A2 with C1, because both break shipped behavior and A2 decides
   the shape of the rule driver that cleanup will reorganize.
2. Section B: land the four decisions as the last behavior batch, with the
   Map key policy for numeric equality decided first, or record each as
   deferred past the cleanup phase.
3. A3 with C7, and A4, in one module batch; A5 and A9 as small cleanup-walk
   repairs; A11 and A12 as deletions.
4. Decide C2, C3, C5, C6, and C8 as keep-or-finish before file moves start.
5. Section E as one documentation pass, then section D as the cleanup
   backlog, beginning with the one-owner rows in C4 and the duplicate
   `$error.apply.arity`.
