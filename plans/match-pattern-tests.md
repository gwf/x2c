# Match lowering through pattern tests

> Status: active
> Proposed 2026-10-26; awaiting Gary's approval. Measured at `76bc02a81`.
> Later `dev` commits through `169ea7882` removed repeated Match machine
> state checks, which may lower the baseline slightly; not remeasured.
> Replaces the binder-free `!or` plan published in `76bc02a81`. A scratch
> prototype was built, verified, and measured; nothing is implemented.

## Result

`match` statement arms and `~=` pattern conditions with static patterns
are tested in place for every Match operator: `!or`, `!and`, `!not`,
`!set`, `!is`, `!quote`, leading binders, binders inside alternatives, and
repeated binders. Only patterns that need a segment search still call the
Match runtime. Match semantics, diagnostics, and public runtime signatures
do not change.

The design takes its representation from the V1 match compiler
(`~/Git/old-x2c/x2c-v1/src/compile.x`). V1 first compiled each pattern into
`AND`, `OR`, and `NOT` of small tests on numbered positions, and only then
wrote C. Every operator is then ordinary boolean structure, so no operator
needs a runtime fallback. This plan keeps that representation and writes
it with the current primitives.

## What is taken from V1, and what is not

| V1 choice | Decision | Reason |
| --- | --- | --- |
| Pattern to AND/OR/NOT tests on positions | Adopt | Puts every operator inline |
| `List.bind` binding list, saved per arm | Replace with C locals | V1 allocated per binder and per match |
| `Var_equal` for every literal | Replace with Symbol bits | Current code already compares bits |
| No switch on the head Symbol | Keep the switch | Current dispatch is cheaper |
| Cursors computed eagerly, shared by arms | Compute lazily per path | Same result, no work before a failed head |
| Prefix factoring of consecutive arms | Do not adopt now | Evidence below bounds it near 1% |
| No runtime fallback | Keep the Match fallback | V1 mis-indexed interior `*` segments |

Each V1 `match` execution also called `List_cons` and walked the whole
subject with `List_len` to size an `alloca` buffer. That runtime overhead,
not the representation, is the likely reason earlier ports measured slow.

The factoring bound: one compiler self-translation executes 53.9 M `match`
statements and tests 43.3 M arms inline, measured with counters added to a
scratch build. At an estimated 10 to 30 instructions per inline arm test,
all inline matching costs about 0.4 to 1.3 G of the 105 G total, and
factoring can remove only part of it. The same build sent 27.4 M arms to
the Match machine; that is the cost this plan removes.

## Design

### Test tree

`_match_arm` compiles the pattern value into a List of tests before it
writes any C. A *cell* names the cursor whose head holds a value, or is
`""` for the subject itself.

| Test | C condition |
| --- | --- |
| `(and T ...)`, `(or T ...)`, `(not T)`, `(true)` | `&&`, `\|\|`, `!`, `1` |
| `(some CELL)` | the cursor is not NULL |
| `(end CELL)` | the cursor is NULL |
| `(listp CELL)` | `Var_is(value, <list>)` |
| `(bits CELL SYMBOL)` | `value.u64 == SYMBOL bits` |
| `(equal CELL PREFIX PATH)` | `Var_equal` with the same cell of the cached pattern |
| `(tag CELL TAG)` | `Var_is(value, TAG)`, with `varray` and `vmap` canonical |
| `(kind CELL PREDICATE)` | `Var_is_atom_binder` and the other `!is` kinds |
| `(atom CELL)` | `!Var_is(value, <list>)` |
| `(bind CELL BINDER)` | assign the binder's local, or compare a bound one |
| `(rest CELL BINDER)` | assign a final `*name` from the cursor |

A List pattern becomes `some` and the element's tests for each element,
then `end`, unless the List ends in `*` or `*name`. A guard follows Match's
normalization: `(OP ?b PAT ...)` binds `?b` and then tests `(OP PAT ...)`.
`!or` and membership `!set` become `or`; `!and` becomes `and`; `!not`
becomes `not` of `or`; `!quote` compares its operand as a literal. A guard
at the pattern's root, such as `(!set ?whole (node ?a ?b))`, tests the
subject itself.

The arm keeps its Match site for an interior `*` or `*name`, a repeated
`*name`, an `x2c-dyn` part, an unknown `!is` shape, a non-static pattern,
or the empty pattern `%()`.

### Writing C

The writer turns the tree into one condition. It assigns a cursor on first
use, as `(cursor = previous->cdr, 1) &&` or through `Var_list_payload` for
a nested List. It tracks two sets along each path: the cursors already
assigned, and the binders already set. An `or` alternative or a `not`
operand works on copies of both sets. After an `or`, the binders that every
alternative set stay set. The second occurrence of a binder therefore
compares with `Var_equal`, as Match's slot comparison does, and that
decision is made at compile time.

Each arm declares its binder locals before the condition, so a binder can
be assigned inside an alternative:

```c
{ Var _x2c_gensym_match_value_0; List _x2c_gensym_match_list_1;
  if (CONDITION) { BODY break; } }
```

The local names keep the current numbering, by position in
`MatchCaptureLayout`'s definite list, so the arm body and typed captures
are unchanged. A binder that is not definite gets a scratch local.

### Switch labels

The `switch` on the head Symbol stays. An arm whose head is an `!or` of
literal Symbols labels each alternative that no earlier arm labelled. Any
other head that is not one Symbol takes `default` and ends labelling, as
today.

### Macro-valued cases

The prototype still uses `_match_nested` for macro-valued (viewed) cases.
The implementation must route them through the same writer, which differs
in three places:

- the root cursor is `_x2c_gensym_match_cursor`, which
  `Macro_case_root` already positioned;
- a nested List is entered with `Macro_case_enter`;
- a binder is written to its capture-buffer slot.

`_match_nested`, `_match_element`, `_match_bind`, and `_match_and` are then
deleted.

## Evidence

All measurements were taken on this Mac with Apple clang `-O2`, at
`76bc02a81`. The baseline, the binder-free `!or` prototype, and this
prototype ran in three converged scratch trees: each passed
`make stage-diff-0` after two bootstrap refreshes. The trees sat at paths
of equal length, and each had its own `X2C_CACHE_DIR` and a warmed output
directory. Each tree's stage 0 translated its own 62 compiler sources with
`-j 1`, in seven alternating rounds.

| Tree | Median instructions | Median cycles | Static Match sites |
| --- | ---: | ---: | ---: |
| Baseline | 105.22 G | 28.32 G | 331 |
| Binder-free `!or` | 102.31 G (-2.8%) | 27.40 G | 258 |
| Pattern tests | 99.36 G (-5.6%) | 26.79 G | 38 |

The instruction spread within each tree was under 0.3%. In a profile of
the same workload, time under arm Match sites fell from 6.2% of samples to
0.5%.

Per call, instructions retired, on `(struct (binding Foo 3) field)` unless
another key is named:

| Pattern | Baseline | Pattern tests |
| --- | ---: | ---: |
| `((!or struct union) (!or (binding ? ?) (gensym ? ?)) ? *)` | 1,574 | 128 |
| Same pattern, miss on `(typedef Foo)` | 203 | 23 |
| `(struct (!or (binding ? ?) (gensym ? ?)) ?)` | 1,382 | 127 |
| `(struct (binding Foo 3) field)` | 169 | 169 |
| `(struct (binding ? ?) ? *)` | 124 | 123 |
| `(? ? ? *)` | 12 | 12 |

Patterns that were already inline cost the same.

Of the 38 remaining static sites, 14 are source arms with an interior `*`
segment; `linked-meta` compiles some of those arms a second time. The rest
were not classified one by one.

Correctness:

- Two differential probes were compiled by the baseline and the prototype
  and printed identical output (155 and 65 lines). Every arm matched at
  least one input, except `dyn` arm 1, `more` 9, and `more` 11. They cover
  every operator, leading binders on `!not` and `!and`, binders inside and
  across alternatives, repeated binders, root guards, typed captures,
  `Var` subjects, and `~=` conditions. The probes are in
  `.context/match-tests-probes/` in the planning worktree.
- `make verify` passed: 1,047 unit tests, 1,294 compiler fixtures, and the
  probe suites. Only 13 of 2,859 fixture artifacts changed, all generated
  C, emit, or transform text; no stdout, status, or diagnostic changed.

Size: the prototype grows `src/components/pattern-match.x` from 532 to 843
lines. Routing macro-valued cases through the writer deletes about 150
lines of the old walker, for an expected total near 690 lines. The
prototype patch is `.context/match-tests-prototype.patch`.

## Implementation

1. Add the test tree and writer to `src/components/pattern-match.x`, as in
   the prototype. Route arms and `~=` conditions through `_match_arm`.
2. Route macro-valued cases through the same writer and delete
   `_match_nested`, `_match_element`, `_match_bind`, and `_match_and`.
3. Regenerate `src/linked-meta.x` with `tools/gen-linked-meta.sh` through
   its Makefile target.
4. Extend `unittest/test-match-stmt.x` from the two probes. For each
   pattern and input, assert that the `match` statement agrees with
   `List.try_match` on the same pattern. `List.try_match` still uses the
   Match runtime, so each assertion compares the two implementations.
5. Commit, then run `make bootstrap-refresh && make build-safe` until
   `make stage-diff-0` passes. Then run `make verify-fixtures-update` and
   review the changed artifacts. Expect generated C only.
6. Repeat the converged three-tree measurement above. Expect about 5.6%
   fewer instructions.
7. Update the paragraph on patterns tested in place in
   `docs/src/guide/match.md`, the match lowering paragraph in
   `docs/src/internals/architecture.md`, and the component's header
   comment.
8. Review and fix the completed authored diff. Then run
   `tools/gate-state.py ensure agent-pr-check` and the performance
   checkpoint in `agents/performance-checkpoints.md`.

## Later candidates

These candidates are not part of this plan. Each needs its own approval.

- `List.match` method calls with fixed patterns, such as
  `Type.is_bare_typedef_name` and `Type.is_static` in `lib/type.x`, take
  1.4% to 1.8% of samples and still call the Match runtime. Those used as
  conditions could become `~=` and gain this lowering.
- V1's prefix factoring of consecutive arms. The test tree makes it
  possible, but the inline-arm counts above bound its gain near 1%.

## Plan review

- Trusted facts: `Code.is_static_pattern` and the cached-pattern check
  establish a fixed pattern. `MatchCaptureLayout` establishes definite
  binders and their numbering. Match's normalization and `_compile_or`
  define leading binders and first-success order. The compiler's binder
  diagnostics already reject maybe-bound names. The writer adds no runtime
  check of these facts; it refuses only shapes it does not write.
- Reuse and deletion: the change reuses the switch, the Match-site
  fallback, the capture layout, and the binder numbering. It replaces the
  ad hoc walker in `_match_nested` with one representation for all
  operators. The new lasting mechanisms are the test tree and the two path
  sets. Each is needed so that alternatives and negations can test cells
  and set binders without changing what later tests see.
- Idiom: the test tree is an ordinary x2c List matched with `match`, and
  the writer is the component's existing C-text lowering. It adds no
  framework or runtime machinery.
- Validators, diagnostics, and fixtures: none are added. The new unit
  assertions compare the inline tests with the Match runtime on the same
  patterns, which protects against wrong match results.
