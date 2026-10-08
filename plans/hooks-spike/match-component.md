# Patterns as one component: `match`

> Status: reference
> Wave 3 worker W3-A of `execution.md`, on private branch `w3a-patterns`
> from `gwf/hooks-spike` `eaee0a7e`, 2026-10-07. The component is
> `match-component.x`; its test is `match-component-test.x`.

## Result

A `match` whose arms are all static patterns becomes ordinary x2c control
flow through the typed node hook, with no Match runtime call. The component
is 215 lines with its comments. It preserves the
book's semantics on every check below. Translation costs 52.2 M
instructions per use, against 12.4 M for the built-in lowering, because the
compiler binds and types the generated tests; the same code written by hand
costs 45.1 M. The generated code runs 9 to 11% faster than the
built-in's.

## API entries

- `hook <match> f;`: `match` joins `switch` in `typed_hook_kinds`
  (src/macros.x). The hook receives `(match SUBJECT ((PATTERN BODY) ...))`;
  a guarded body is `(guarded (if GUARD (block BODY (break))))`, and the
  default arm's pattern is `(*)`.
- `x2c_pattern_value(pattern)`: new. A bound pattern holds its literal
  parts as `(cache N)` entries, which only the compiler can read. The
  operation returns `Compiler.match_pattern_value`, the value graph binder
  analysis already uses, with `x2c-dyn` for computed parts. Prototype in
  lib/meta.x ("patterns"), answer in src/compiler.x beside
  `match_pattern_is_static`, and a one-line forwarder in etc/meta-helper.x.
  Its owner is src/meta-sdk.x; it sits in compiler.x only because
  meta-sdk.x belonged to another worker in this wave.
- No pattern helper went into lib/meta.x. The pattern compiler emits steps
  for a `match` arm in place; a catch predicate would need the same steps
  as one expression, so a shared form waits for that second client.

## Lowering

```x2c
{
  List subject = SUBJECT, cursor0 = subject, cursor1 = subject;
  switch (0) {
    default:
    { cursor0 = subject;
      if (cursor0.car().u64 == ((Var) <a>).u64) {
        cursor0 = cursor0.cdr();
        if (cursor0) {
          Var x = cursor0.car();
          cursor0 = cursor0.cdr();
          if (!cursor0) { BODY; break; } } } }
    { ... next arm ... }
    { DEFAULT BODY; break; }
  }
}
```

One cursor per List depth walks the cells; each nested List pattern
assigns the next cursor. A failed test falls out of its arm into the next.
`switch (0)` gives the cleanup barrier that `Walk._rewrite_matchcases`
gives: `break` leaves the match and `continue` reaches the loop. Only `?`
and binders test that an element is present, because `car` of an empty
List is `void`, which no literal, tag, or List test accepts. The subject
and cursors are fresh names.

## Pattern forms

Covered, by element of a List pattern:

| Form | Test |
| --- | --- |
| literal Symbol | `value.u64 == ((Var) <sym>).u64`, the runtime's bit mode |
| other literal (number, String, long Atom) | `value == ` the same element of the runtime pattern |
| `?`, `?name` | presence; a repeated name compares by `==` |
| nested List pattern | `value is <list>`, then its elements |
| `?(T name)`, `(!is type T)` | `value is <T>`; `varray` and `vmap` read as `array` and `map` |
| final `*`, `*name` | binds the rest of the List |

Declined, so the match compiles as before:

- An interior star: a correct split needs a search with backtracking.
- `!or`, `!and`, `!not`, `!set`, `!quote`, and other `!is` forms. `!or`
  and `!set` with binders need per-alternative binding; none was needed to
  prove the claim.
- A guard operator at the root, a computed part (`$x`), and a
  macro-valued case.
- A repeated `*name`: its span comparison has its own rule.
- Arms between preprocessor directives.

Two choices follow from the compiler's current data:

- Non-Symbol literals compare with the runtime pattern rather than with a
  literal the component writes. The value graph holds a number as its
  digit String, so `3` and `"3"` look alike. The runtime pattern is a
  static List, and its element is the exact value the matcher compares.
- A binder is declared by its spelling, as the built-in emitter declares
  it. One binder can carry two binding identities in the bound body: an
  identifier resolved while parsing, and one in a string interpolation
  resolved while binding. A declaration by identity covers only one.

## Checks

| Check | Result |
| --- | --- |
| `match-component-test.x` with and without the include | outputs equal; 9 of 10 matches lowered |
| 11 match fixture programs with expected stdout, each with the include | all equal their `.stdout`; 21 matches lowered, 13 declined |
| a unit of declined matches with and without the include | function C byte-identical |
| typed switch and match component in one unit | output equal |
| `typed-switch-test.x` | `ok` |
| 28 match, switch, and typed-hook fixtures, stage 2 | 28 pass |

The test covers arm order, every covered literal kind, nested Lists, the
default, a guard that is false (next arm) and a guard's run count, binder
shadowing, `break`, `continue`, `defer` on both, no match without a
default, a nil subject with `*rest`, a repeated typed capture, a nested
match, a `Var` subject, and one subject evaluation per match. With stage 0,
three fixtures differ only in origin and binding numbers: lib/meta.x
differs from the bootstrap, so the prelude is parsed in process.

## Cost

Converged stage-2 compiler of this branch (stage 1 and stage 2 translate an
empty unit in 1.89 G instructions; stage 0 takes 8.95 G).
`bench/measure.sh`, one warm-up and the minimum of five; units from
`bench/gen-match.py`, one four-arm match per function: a flat arm, a nested
List with a final star, a typed capture, and a default. Slope from N=50 to
N=400:

| Unit | N=50 | N=400 | Per use | Real time per use |
| --- | ---: | ---: | ---: | ---: |
| Built-in `match` | 2,581,312,983 | 6,915,385,437 | 12.38 M | 0.77 ms |
| Component | 5,194,113,939 | 23,446,087,161 | 52.15 M | 3.77 ms |
| The component's code by hand | 4,215,005,168 | 20,014,176,818 | 45.14 M | 3.03 ms |

A declined match costs 3.1 M over the built-in (a variant that declines
every match: 15.51 M per use). Reading the patterns, three pattern-value
queries, and three fresh names cost 0.8 M (a variant that builds the result
and declines). The rest is binding, typing, and lowering the returned code.

How the result is built decides most of the cost:

| Construction | Per use |
| --- | ---: |
| One `&&` expression per arm, repeating `cdr` chains | 126.7 M |
| Nested `if` steps built by quotations | 76.7 M |
| The same steps as canonical syntax | 55.1 M |
| Canonical syntax without redundant presence tests | 52.2 M |

Each quotation lands as a template application, and an arm holds dozens.
Calling `List_car` instead of `.car()` saved 1.2 M and was not kept.

Generated code, `bench/match-runtime.x`, one call on each of four subjects
for 10,000,000 rounds, minimum of three runs, in two sessions: built-in
27.9 and 25.9 ns per match, component 24.7 and 23.5 ns. The built-in calls
the Match runtime for the nested arm. `bench/match.sh COMPILER` repeats
every measurement here; a second run agreed within 0.1 M per use.

## Limits and defects found

- Defect in the built-in lowering, reproduced without the component: a
  `defer` in a `match` arm that reads an arm binder fails in C with "use
  of undeclared identifier". A `defer` reading an ordinary local works. The
  component inherits it, because it declares binders by spelling.
- A parse error in a meta function of an included file is not reported.
  The hook then fails with "this function cannot run at compile time" and
  an undefined-symbol link error naming the helper function.
- Translation per use is four times the built-in's. A typed-phase
  component pays to bind the code it returns; the built-in emitter writes
  its tests as C text.
- `x2c_pattern_value` returns digit Strings for numbers; a component that
  must write a numeric literal itself cannot tell `3` from `"3"`.
