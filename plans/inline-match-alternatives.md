# Inline `!or` in match statements

> Status: active
> Proposed 2026-10-26; awaiting Gary's approval. Measured at `c8d554643`
> and rechecked against `dev` `988f0734c`, which added pattern conditions.
> A scratch prototype was measured and verified; nothing is implemented.

## Result

A `match` statement arm or `~=` pattern condition whose static pattern uses
`!or` with binder-free alternatives is tested in place, by direct C tests on
cursors, instead of calling the Match runtime. Match semantics, diagnostics,
and public runtime signatures do not change. Only the generated C and its
speed change. Pattern conditions (`_match_condition`) call the same
`_match_nested` and Match-site fallback as arms, so they gain the change
without separate code; they have no switch labels.

Today `_match_element` in `src/components/pattern-match.x` returns -1 for
any match operator, so one `!or` sends the whole arm to
`x2c_match_site_try_capture` and the wordcode machine. The machine costs
about 400 instructions per call plus about 55 per word. The match-component
plan (`plans/archive/match-component.md`) listed alternation among the
patterns that keep a Match site, but recorded no technical reason.

Two facts make the inline form correct. `_compile_or` in
`lib/match/plan.x` returns at the first successful alternative, so `!or`
never backtracks, and a C `||` has the same order and cut. The book requires
a binder under `!or` to occur in every alternative
(`docs/src/guide/match.md`), and this plan admits only alternatives without
binders.

## Evidence

All measurements are on Apple clang `-O2` on this Mac, at `c8d554643`. The
prototype patch is `.context/inline-or-prototype.patch` in the planning
worktree. It is a measured reference, not the code to ship.

Per call on `(struct (binding Foo 3) field)`, instructions retired, slope
between 1 M and 6 M calls:

| Pattern | Today | Prototype |
| --- | ---: | ---: |
| `((!or struct union) (!or (binding ? ?) (gensym ? ?)) ? *)` | 1,575 | 129 |
| `((!or struct union) ? ?)` | 947 | 23 |
| `(struct (!or (binding ? ?) (gensym ? ?)) ?)` | 1,382 | 127 |
| Same pattern, miss on `(typedef Foo)` | 202 | 22 |
| Four plain arms, written by hand, hit | 135 | 135 |

The prototype on six keys agreed with the runtime matcher.

Compiler self-translation: each tree's stage 0 translates its own 62
sources with `-j 1`. Both trees are converged, at paths of equal length,
with separate `X2C_CACHE_DIR` directories and warmed output directories.
Seven alternating rounds:

| Tree | Median instructions | Median cycles |
| --- | ---: | ---: |
| Baseline | 104.92 G | 33.18 G |
| Prototype | 102.04 G | 31.98 G |

The prototype retires 2.88 G (2.7%) fewer instructions. The instruction
spread in each tree is under 0.4%; the cycle numbers vary more and only
agree in direction. Match-runtime functions fell from 7.8% to 5.6% of
profile samples. Compiler C has 257 static Match sites instead of 329, and
`lib` has 0 instead of 1.

Correctness of the prototype: after two bootstrap refreshes
`make stage-diff-0` passed, so the tree reproduces itself. `make verify`
passed: 1,047 unit tests and 1,293 compiler fixtures with their checked-in
artifacts. The stage-1 compiler also built and translated itself.

A trap for the A/B: before the bootstrap refresh, stage 0 walked the
prelude cold on every run and read 6% *slower*. Measure only converged
trees. The archived risk that editing a shipped component breaks
`make build-safe` from a stale seed did not reproduce; the first build
passed.

## Design

Supported alternatives, inside a non-viewed static pattern of a `match`
statement arm or a pattern condition:

- a literal Symbol, compared by bits;
- any other literal atom, compared with `Var_equal` against the same cell
  of the cached pattern, as `_match_nested` already does;
- `?`, which writes no test;
- a nested List of supported parts, with an optional final `*`;
- a nested `!or` of supported parts.

The arm keeps its Match site when an `!or` holds a binder, has a leading
binder, holds another operator (including `!quote`), holds an interior `*`,
or has no alternatives. Macro-valued (viewed) cases, catch patterns, and
`List.match` method calls are unchanged.

The C for `(!or A B)` at a cell is `(TEST_A || TEST_B)`. A List alternative
assigns the next cursor inside its own disjunct, so each alternative starts
from the cell again. Binders elsewhere in the arm work as they do today,
because no binder is ever written inside the disjunction.

One owner tests each element. The `!or` case belongs beside the other
element tests in `_match_element`. A List alternative is walked by the same
code that walks a nested List in place. Make that walk recursive per List,
so an alternative and an in-place sublist share it, and delete the `rests`
and `paths` stacks in `_match_nested`. The walk gets one flag that refuses
binders inside an alternative. Literal comparison against the cached
pattern moves into one helper that both callers use. If the recursive walk
is not shorter than the prototype's separate helper (62 lines), keep a
separate binder-free helper instead and record the line counts in the
change.

Switch labels: `_match_label` takes the arm's pattern value. When the head
is an `!or` whose alternatives are all literal Symbols, it labels each
alternative that no earlier arm labelled. Any other head without one Symbol
takes `default` and ends labelling, as it does today. The labels are valid
whether the arm is tested in place or at a Match site.

## Implementation

1. Change `src/components/pattern-match.x` as designed. Update its header
   comment, which the generated `docs/src/internals/compiler-api/` page
   copies.
2. Regenerate `src/linked-meta.x` with `tools/gen-linked-meta.sh` through
   its Makefile target. Never edit it by hand.
3. Add arms to `unittest/test-match-stmt.x`:
   - an `!or` head before, between, and after arms with the same heads;
   - Symbol, String, and number alternatives;
   - List alternatives with `?` and a final `*`;
   - a nested `!or`;
   - an arm with ordinary binders beside an `!or`;
   - a leading-binder `!or` that still takes the runtime path;
   - a `~=` pattern condition with an `!or`.
4. Converge the emission change: commit, then
   `make bootstrap-refresh && make build-safe` until `make stage-diff-0`
   passes. Two rounds were needed in the prototype.
5. Repeat the converged self-translation A/B above. Expect about 2.7%
   fewer instructions.
6. Update `docs/src/guide/match.md` (the paragraph on patterns tested in
   place) and `docs/src/internals/architecture.md` (the match lowering
   paragraph) to include binder-free `!or`.
7. Review and fix the completed authored diff. Then run
   `tools/gate-state.py ensure agent-pr-check` and the performance
   checkpoint in `agents/performance-checkpoints.md`, because the change
   affects generated code and compiler throughput.

## Later candidates

These candidates are not part of this plan. Each needs its own approval.

- Leading binders: `(!or ?tag a b)` and a binding `(!set ?b TEST)` bind
  the tested cell, and `_match_bind` can bind it after the test. A rough
  source count finds 37 and 87 such arms. `_visit` in
  `src/generate/dependencies.x` is the hottest remaining statement site. Not
  measured.
- `List.match` method calls with static patterns, such as
  `Type.is_bare_typedef_name`, `Type.is_pointer`, and `Type.is_static` in
  `lib/type.x`. These took about 1.3% of the prototype's samples, and none
  of them goes through `pattern-match.x`.

## Plan review

- Trusted facts: `Code.is_static_pattern` and `_match_nested`'s cached
  pattern check establish a fixed pattern. `_compile_or` establishes
  first-success order. The compiler's binder diagnostics already establish
  that `!or` binders occur in every alternative. The lowering adds no check
  of these facts and refuses only shapes it does not emit.
- Reuse and deletion: the change reuses the existing cursors, literal-cell
  comparison, labels, and Match-site fallback. The recursive walk replaces
  the `rests` and `paths` stacks instead of adding a second walker. The
  only new mechanism is the alternative flag, needed because a disjunct
  cannot hold a binder's declaration.
- Idiom: the result is the component's existing C-text lowering extended
  by one element form. It adds no framework, cache, or runtime machinery.
- Validators, diagnostics, and fixtures: none are added. The new unit arms
  protect generated-code behavior: arm order across shared heads, literal
  kinds, and the runtime fallback.
