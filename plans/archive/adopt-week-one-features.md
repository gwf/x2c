# Adopt the first week's language and library features in src/ and lib/

> Status: done
> Written 2026-09-09 in the oslo workspace from a survey of every commit on
> `main` since the 2026-09-05 release (4235c38..2f74dec). Approved by Gary
> the same day with Phase 0 added and delivered to `main` the same day as
> the commit series 06d0787..d02e75f (four phases, artifact sync, and two
> bootstrap refresh rounds); `agent-pr-check` green at d02e75f. The
> exceptions recorded under Phase 2 and Phase 3 are follow-on candidates.

## Result

The compiler and runtime use the features shipped this week the way the
book now recommends. No public behavior, ABI, or generated-header contract
changes. Generated C for `src/` and `lib/` is identical except at the sites
named below, and the self-translate diff shows exactly those sites.

Features shipped this week and their adoption sites in hand-authored code:

| Feature | Landed | Real sites | Marginal |
| --- | --- | --- | --- |
| `_Static_assert` at file, block, struct scope | e6efc74 | 17 | 0 |
| C literal `==`/`!=` a `String` converts the literal | bb3de5b | 13 `strcmp` + 115 `%"lit"` | 0 |
| `?(Type name)` typed match captures | 49d46e8, 351eebc | ~45 | ~4 |
| `case ... if (expr):` arm guards | 49d46e8 | 8 | 3 |
| wildcard `catch %(?code *detail)` | bb3de5b | 3 sites (one deletes a 20-code macro) | 8 |
| `Array.sort_by`/`sort_with`, `List.sort_by`/`sort_with` | 1de90da | 7 (all in tools/x2c-graph) | 3 |
| chained designators `{ .a.b = x }` | e6efc74 | 2 | 6 |
| mixed operator operands via converter | 5344953, d6776bb | 1 (example) | 1 |
| `arr[i] += v`, `map[k] += v` | pre-week (collections.md now documents it) | 1 | 0 |
| adjacent C string literals | e6efc74 | 0 | 1 |

Autodiff, direct flat-match emission, Var boxing without tag lookup, editor
support, and the c* and sqlite packages are compiler-internal or external and
need no source adoption.

## Settled choices

- **Typed captures keep direct emission (Phase 0).** `?(String a)` lowers
  at parse time to `(!is ?a type <string>)` (`src/literals.x:149`). The flat
  classifier `Compiler.match_pattern_flat_head` (`src/compiler.x:1114`)
  accepts only bare atom binders after the head, so a typed arm falls to the
  runtime matcher today. That was reuse, not a blocker: `v is String` already
  emits a single `Var_is(v, TAG)` compare and the tag is a Symbol literal by
  emission time. Phase 0 lets the classifier accept `(!is ?name type
  <literal>)` elements and has `_flat_match_condition` emit the `Var_is`
  clause. A deferred `<macro-expr>` type tag keeps the runtime path.
- **Do not retype untested `?name` captures.** Adding `?(String a)` to an arm
  that captured a bare `?a` adds a tag test the arm does not perform today.
  Only existing `(!is ?name type T)` predicates convert; the rewrite is a
  spelling change and, after Phase 0, a direct-emission win where the arm is
  otherwise flat.
- **Widen a catch only where the body already means "any cause".** The
  two- and three-arm filters in `src/collect.x`, `src/frontend.x`, and
  `src/macros.x` are deliberate cause lists; a wildcard would also consume
  allocation and other causes those sites let propagate. They stay.
- **Replace `%"lit"` with `"lit"` in comparisons.** Probe (`/tmp/oslo/cmp.c`
  from `builds/0/x2c translate`): both spellings emit the same promoted
  constant and `String_equal` call, so the change is spelling only. The
  `strcmp(s, "lit") == 0` sites change from `strcmp` to `String_equal` on an
  interned String; that is the documented comparison and the only emitted-C
  change in this group. Gary may veto the 115-site `%"lit"` sweep without
  affecting the rest of the plan.
- **`_Static_assert` replaces the negative-array-size typedef idiom.** The
  15 `x2c_var_abi_*` typedefs in `lib/common.x:34-63` and the two in
  `lib/string.x:98` and `lib/pool.x:82` become assertions with a message.
  Header placement follows the typedef rule already in the language
  reference; the implementing session confirms the emitted `common.h`
  still carries the assertions that guard the public ABI.
- **Typed-array `sort_by`/`sort_with` is out of scope.** The survey found
  that `lib/array-generics.xmacro` has no sort; that is a new feature, not
  adoption, and is recorded here as a follow-on candidate only.

## Implementation

Four commits, each validated and delivered to `main` in order. Phase 2
depends on Phase 0; the others are independent.

### 0. Direct emission for typed flat captures (src/)

- `src/compiler.x` `match_pattern_flat_head`: accept an element of the form
  `(!is ?name type <tag>)` where `<tag>` is a Symbol literal, in addition to
  a bare atom binder, and keep the definite-binder correspondence.
- `src/emit.x` `_flat_match_condition`: for a typed element, add
  `Var_is(_x2c_match_cursor->car, BITS)` before the capture store, using the
  same spelling the `is` operator emits.
- Fixture: extend `unittest/compiler-fixtures/match-typed-guards.x` (or add
  a sibling) with a typed flat arm and check the emitted C carries no
  `MatchCaptureSite` for it. `unittest/test-match-stmt.x` gains the typed
  and guarded flat cases beside the existing direct-check tests.

### 1. C-compatibility features (lib/, src/)

- `lib/common.x:34-63`, `lib/string.x:98-99`, `lib/pool.x:82-84`: replace
  each `typedef char name[(cond) ? 1 : -1];` with
  `_Static_assert(cond, "message");`. Messages state the ABI fact.
- `lib/func.x:78-80` and `:89-92`: return compound literals with chained
  designators (`(FuncArg) { .data.value = value }`,
  `{ .data.reference = reference, .reference_type = type }`).
- `src/cli.x:868,879,940,944,948,957,958,966` and `src/project.x:194-195`:
  `strcmp(x, "lit") == 0` becomes `x == "lit"` (all operands are `String`).
- 115 `x == %"lit"` / `!= %"lit"` sites (list in the survey table: project 27,
  transform 15, build 13, expressions 9, generate 8, cli 6, macros 5, ast 4,
  parse 4, compiler 4, collect 3, statements 3, tokenizer 3, cache 2,
  protocol 2, literals 2, lisp 2, toolchain 1, emit 1, bootstrap 1): drop
  the `%`. Interpolated `%"...${...}"` operands are not literals and stay.
- `examples/magic/autodiff.x:13-15`: remove the `Dual three = 3.0` local and
  write `x * y + 3.0` and `t > 3.0`, matching the `double` version below it.

Expected self-translate diff: `_Static_assert` lines, two `FuncArg`
initializers, and `String_equal` replacing `strcmp` at 13 call sites.

### 2. Match captures and guards (src/)

Convert every named `(!is ?name type T)` whose binder is used as a `T`, and
delete the conversion the body performed. Sites by file, from the survey:

- `src/protocol.x`: 135, 137, 146, 285, 520-546 (participant, base,
  representation, tag, location lists), 577, 1414, 2219-2222 (owner across
  two `!or` alternatives, plus a guard `if (owner == participant)`);
  1159-1161 folds `status != <sig-cnflct>; continue` into the pattern.
- `src/transform.x`: 1456, 1512, 1770; 1634-1637 and 1794-1796 become
  `?(List x)` with an `if (x.match(...))` guard and lose their temps.
- `src/expressions.x`: 709, 934, 1477, 1480, 1610, 1736, 2305.
- `src/parse.x`: 126, 127, 1549, 1559; 1883 drops an unused binder.
- `src/macros.x`: 691-692, 1340; 275 and 1097 return `Var` and stay.
- `src/collect.x`: 439, 671, 676-681 (`?(Map ...)`, `?(String ...)`);
  443 drops an unused binder.
- `src/compiler.x`: 1525-1529; 2067-2071 moves the `continue` test into a
  guard.
- `src/generate.x:511-512`, `src/literals.x:975-976, 1055-1056`,
  `src/ast.x:48-52`, `src/snapshot.x:77, 155`, `src/lambda.x:78-81`.

Not converted, with the reason: `src/parse.x:1546` (`?owner` spans string
and symbol tags), `src/macros.x:2487` (`type atom` is a category), every
`!set` slice binder, and every untested `?name` later assigned to a typed
local (`src/generate.x:221, 242`, `src/cache.x:475`,
`src/expressions.x:2130, 2304, 2345`, `src/transform.x:1253, 1299`).

Found during implementation, and left as explicit `!is` spellings:

- `src/protocol.x:2219` keeps `(!or (!is ?owner ...) ((!is ?owner ...)))`.
  The runtime reads `(!or ?binder alternative)` as bind-and-match rather
  than as two alternatives, so `%((!or ?(String owner) (?(String owner))))`
  never matches; the typed lowering in `_typed_pattern` follows the same
  reading. Probe: `(!or ?owner "x")` fails on `"T"` while
  `(!or "x" ?owner)` matches. A design decision, not adoption.
- An unused binder in a flat arm stays named (`src/parse.x:1883`
  `?(String directive)`): the anonymous `(!is type string)` form is not a
  flat capture and would send the arm back to the runtime matcher.
- The shorthand's pattern List is built per evaluation for runtime-matched
  arms (`List_var(cons(...))`) because `_typed_capture_pattern` wraps the
  tag as a cached `(var ...)` element; the explicit `(!is ?x type string)`
  spelling is a constant. Across `src/` the self-translate count rose from
  1387 to 1450 such constructions. Dropping the wrap made it worse (1538)
  and changed direct emission, so it stays; recorded as a follow-on.
- Fixture checks need `make hdr-sync` after `src/` edits: a stale
  `etc/header-symbols.xlisp` made 31 fixtures fail with renumbered bindings
  and a synthesized `String_c_len` prototype.

Expected self-translate diff: arms with a literal head and single-element
captures move from `x2c_match_site_try_capture` to direct checks; other
arms lose only their conversion calls; guards emit the same `if`.

### 3. Wildcard catch and stable sorts

- `lib/func.x:182-205` stays as five arms. A wildcard arm cannot re-raise
  under the caught code: the `raise` statement requires a bare Symbol code
  (`raise %($code ...)` is a parse error), and `Error.raise(code, detail)`
  records no source location, which the docstring says to prefer keeping.
  Recorded as a language follow-on: a `raise` form that takes a computed
  code and keeps the site record.
- `examples/programs/lisp.x:11-27`: delete the `shell-catches` Lisp macro and
  the `$shell.errors` decorator; the one arm becomes
  `catch %(?code *detail): _print_error(code, detail);`. The four bare
  `catch:` arms at 42, 69, 91, 115 report the actual cause the same way
  instead of "unknown failure". Refresh `examples/expected/` output if the
  wording changes.
- `tools/x2c-graph/x2c-graph.x:1705` (`_ranked_records`) and its five
  producers at 1787, 1833, 1947, 2063, plus
  `tools/x2c-graph/loop-allocations.x:329, 363, 368`: replace the
  decorate-with-`rank`, `.sort()`, strip idiom with `records.sort_by(...)`
  using the same key list. The graph tests under `tools/x2c-graph/tests`
  fix the output order.

### Review before validation

The implementing session reviews the completed diff for leftover
conversion calls (`.str()`, `.list()`, `.symbol()`) on now-typed binders,
for any arm whose direct-check emission was lost, and for `%"` operands that
are interpolations.

## Compatibility

No public API, header symbol, or documented behavior changes. `etc/header-
symbols.xlisp` may change where a helper's docstring text moves; regenerate
through the documented targets. `bootstrap/` changes for commit 1 and 2;
the two-round refresh applies (stage 0 comes from the checked-in bootstrap,
so the first `precommit` fails `stage-diff-0` until the refresh lands).

## Validation

Per commit: `make x2c`, then the fixtures nearest the change
(`match-typed-guards`, `string-literal-comparison`, `c-static-assert`,
`designated-composite-elements`, `unittest/test-func.x`,
`tools/x2c-graph/tests/run.sh`, `examples/programs/lisp` expected output),
then a self-translate diff of `src/` and `lib/` C against `bootstrap/` to
confirm the expected deltas and nothing else. Once per commit before
delivery: `tools/gate-state.py ensure agent-pr-check`.

## Plan review

- **Facts established elsewhere:** the tag test in `?(Type name)` is the same
  `!is` predicate the arms already run; no consumer rechecks it. The
  literal-to-String conversion is established by `_binary_expression`
  (`src/expressions.x:1326`); no site adds a second comparison. The ABI
  facts in `lib/common.x` are asserted once, by the assertion that replaces
  the typedef.
- **Deleted or reused:** Phase 0 adds one clause to an existing classifier
  and one to an existing condition builder; no new traversal or cache.
  ~40 conversion calls in match bodies, five
  duplicate catch arms in `lib/func.x`, a 17-line Lisp macro and decorator
  in the Lisp shell example, one `_ranked_records` helper and eight
  decorate-sort-strip loops, 17 sentinel typedefs, and two temporaries in
  `FuncArg` constructors. No new helper, representation, traversal, or
  cache is added.
- **Idiomatic x2c:** every change spells an existing operation the way the
  book's match, values, exceptions, collections, and from-c chapters now
  describe it; no construct is imported from another language.
- **Validators, diagnostics, negative fixtures:** none added. The
  `_Static_assert` sites replace an existing compile-time check with the
  same check under its standard spelling.
