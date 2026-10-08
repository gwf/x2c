# Static patterns as one entry, and catch selection by predicate

> Status: reference
> Wave 5 worker W5 of `execution.md`, on private branch
> `w5-catch-predicate` from `gwf/hooks-spike` `072ab0ef`, 2026-10-08.
> Bootstrap refreshed and converged on the branch.

## Result

The static-pattern compiler of `match-component.x` is one thin-API entry,
and `catch` is its second client. A catch clause whose filtered patterns
are all in the static subset selects its arm through a generated function
at raise time, with no `MatchPlan`. Every other clause keeps today's path.
All checked semantics are unchanged. Raising and catching is 3 to 5
percent faster. Translation costs 32 M instructions more per try with distinct
patterns, and 7.9 M less when a unit repeats its patterns.

## API

`lib/meta-patterns.x`, an optional library module:

- `x2c_pattern_steps(List pattern, Atom subject)` returns `(STEPS BINDERS
  CURSORS)`, or NULL outside the static subset that match-component.md
  records. A step is `(test EXPRESSION)` or a statement. BINDERS are in
  `Match` capture order. CURSORS are fresh names, the same name at the
  same depth for every pattern.
- `x2c_pattern_nest(List steps, List inner)` returns the block that runs
  `inner` when every test holds.

The entry is pure, so it crosses the helper pipe. Compiled-in code calls
the linked copy. Project meta code asks the compiler through one query
line in `etc/meta-helper.x`. A non-Symbol literal is compared with the
element expression of a `cons`-built pattern, such as a catch filter, or
read at run time from a cached pattern, such as a `match` arm.

Two transitions shaped the entry:

- Bodied `meta` code in `lib/meta.x` that the bootstrap has not linked
  makes every unit need the project helper, including the helper's own
  loop, which then deadlocks on the project lock. A separate module
  avoids this.
- A compiler-owned module's compile-time bodies do not reach the project
  helper; `etc/meta-helper.x` copies `lib/meta.x` bodies by hand. A query
  replaces that copy.

## Catch

`_catch_clause` in src/builtins.x asks `_catch_selector` for a selector.
It returns `(select NAME DEFAULT)` and adds the effects that declare

```c
static int NAME(List error, Var *captures, int *count) {
  List cursor0 = error, ...;
  { steps of arm 0 ... captures[i] = binder; *count = k; return 0; }
  ...
  return DEFAULT;               /* the default arm, or -1 */
}
```

as unit support, keyed by the patterns and default, so equal clauses share
it. `$catch_selector` writes the site `{NULL, DEFAULT, COUNT,
ERROR_CATCH_STATIC, -1, NAME}` and registers with no patterns. A pattern
with more than 128 steps keeps the `MatchPlan` path, which reports a
pattern too large to prepare.

Runtime, lib/error.x: `ErrorCatchSite` gains `select`. `_catch_select`
calls it when present, at the same point in raise-time dispatch as the
plans, and commits captures through the existing `_commit_captures`, which
now takes a count. A selector site is static from the start, so it never
binds or prepares plans, and it is not freed as a per-call site.

Unchanged by construction: dispatch order and the observer rule, arm
order, default last, transient and uncovered clauses, detach before the
arm, replacement raises, capture lifetime.

In the compiler and runtime, 45 of 62 catch clauses use a selector, and
they share 29 selector functions.

## Checks

| Check | Result |
| --- | --- |
| 120 fixtures mentioning try, catch, raise, exception, error, or observers | 102 pass; 18 differ only in `.c` and `.transform` |
| stdout and status of those 18 | identical |
| `make -C unittest test-all`, all suites | 942 passed |
| `make -C unittest error-probes` | pass |
| `make -C unittest meta-helper-probes` | pass |
| catch semantics program, base against head compiler | output identical |
| `match-component-test.x` with and without the include | identical; 9 of 10 lowered |

The semantics program covers arm order, default, no default with an outer
catch, numbers, doubles, Strings, keyed binders, repeated binders, nested
Lists, typed captures, a code binder, shared selectors, a dynamic and an
interior-star clause on the old path, an observer outside a selected
catch, a replacement raise from an arm, `continue` from an arm, and
`finally` before the arm.

Changed expectations, regenerated from the new compiler and not committed:
ast-leaf-contract, c-body-directive, catch-constant-preparation,
catch-filter-runtime-init, cleanup-loop-boundary, defer-array-field-write,
defer-try-cleanup, exception-signal-mask, foreach-macro-lowering,
generated-name-hygiene, goto-cleanup-regions, meta-returned-try,
optional-reference, raise-statement, try-reference-escape,
var-numeric-lowering, volatile-destructure, volatile-indirect-write. Each
diff replaces the pattern array and pending block with the selector site,
appends the selector, and renumbers bindings in `.transform`.

## Cost

Converged compilers of `072ab0ef` and this branch, built from archives at
equal path lengths. `bench/catch.sh COMPILER`: one warm-up and the minimum
of five translations; slope from N=50 to N=400.

| Unit | Base per use | Head per use |
| --- | ---: | ---: |
| c-catch, a different first pattern in each try | 38.64 M | 70.61 M |
| c-same, the same four patterns in each try | 38.59 M | 30.71 M |
| match component, `bench/match.sh` | 52.06 M | 54.57 M |

`catch-runtime.x`, 2,000,000 raises and catches over four static arms,
minimum of three: 3,873.6 ns base and 3,688.0 ns head in one session,
3,869.5 ns and 3,746.5 ns in a second, interleaved. The match component's
generated code is unchanged at 26.3 ns per match.

The distinct-pattern cost is binding, typing, and lowering the selector
function; a sample shows no single hot spot. Canonical syntax instead of
quotations saved about 3 M. The match component pays one query per arm.

Lines, excluding generated files: lib/error.x +32 -8, src/builtins.x
+98 -4, lib/meta-patterns.x +209, etc/meta-helper.x +2, lib/Makefile +1
-1, match-component.x +23 -175.

## Limits

- Translation per try with distinct patterns nearly doubles. A carrier
  entry that accepts lowered code would remove the rebinding.
- The book's sentence that each arm's program is prepared once describes
  the `MatchPlan` path; a selector arm has no program.
- `!or` in the code position, common in src/, stays on the `MatchPlan`
  path, as match-component.md declines it.
