# Match as a component

> Status: reference
> Research on `kernel/match-research` from dev `1829e259`, 2026-10-10. The
> prototype commits are throwaway evidence, not for integration. The
> recommendation awaits Gary's choice; nothing here authorizes delivery.

Question: can `match` become `src/component-match.x`, returning lowered
code, at or under 12.4 M instructions per use and with generated programs
no slower than today? What must the kernel keep?

## Answer

Yes. A shipped component that returns a lowered carrier of C text around
the bound subject, patterns, and bodies translates a match at 4.75 M per
use on a three-arm workload (built-in 4.62 M) and 10.19 M on the spike's
four-arm workload (built-in 12.34 M). It writes static patterns as nested
`if` tests with no Match call, so matches run 3.6 to 10 times faster, and
a compiler built with it translates its own sources 4.5 percent faster.
Only lowered C text meets the budget: lowered expression trees cost 3 to
45 percent more, and source syntax bound by the driver costs 3.2 to 3.8
times the built-in.

## Measurements

Instructions retired on converged compilers, fresh output directories and
unique stems, median of 3. Per use is the slope between files of 0 and
1,000 functions (W3) or 50 and 400 functions (W4). W3 has one three-arm
match per function: `%(add *)`, `%(mul ?x 2)`, and a default. W4 is the
spike's four-arm workload (`gwf/hooks-spike` `bench/gen-match.py`). A
function without a match costs 2.95 M, so the W3 match itself is 1.7 M.

| Variant | Return | Arm tests | W3 | W4 |
| --- | --- | --- | ---: | ---: |
| Built-in emitter (today) | - | C text in emit.x | 4.62 M | 12.34 M |
| Port of the emitter | lowered | C text, Match sites | 4.77 M | 11.05 M |
| Static tests, value buffer | lowered | C text | 4.75 M | 10.13 M |
| Nested tests (recommended) | lowered | C text | 4.75 M | 10.19 M |

An earlier batch, before a List subject was read directly (0.27 M more on
W3), with the built-in at 4.61 M and 12.37 M:

| Variant | Return | Arm tests | W3 | W4 |
| --- | --- | --- | ---: | ---: |
| Rule matched, component declines | - | built-in | 4.70 M | 12.47 M |
| Static tests | lowered | C text | 5.00 M | 10.37 M |
| Static tests, prepared analysis kept | lowered | C text | 5.06 M | 10.50 M |
| Typed trees with C text leaves | lowered | expression trees | 5.15 M | 15.05 M |
| Source syntax, prepared replacements | source | expression trees | 17.59 M | 39.23 M |
| Source syntax, no prepared replacements | source | expression trees | 17.40 M | 37.98 M |
| Nested tests written by hand, built-in | - | source | | 45.66 M |

Prepared replacements refuse a skeleton holding a statement, block, or
declaration, so they never apply to a statement lowering; trying costs
0.19 to 1.25 M on source returns. For a lowered carrier the driver walked
the result in `_template` before refusing; skipping that saves 0.06 to
0.13 M. About 0.09 M of the W3 gap is the rule driver, the per-call match
and Lisp session the foundation plan already lists for deletion. W4 is
cheaper because the built-in emits every arm's pattern, registering its
cached List even for arms that never read it: 161 `cons` calls in the
built-in C for 50 functions, none in the component's.

Runtime, Apple clang `-O2`, median of 5: the W3 program runs 200 functions
on 3 subjects 100,000 times; W4 is the spike's `match-runtime.x`.

| Variant | W3 program | W3 per match | W4 per match |
| --- | ---: | ---: | ---: |
| Built-in | 1.36 s | 22.7 ns | 21.3 ns |
| Port of the emitter | 1.37 s | 22.8 ns | 22.1 ns |
| Static tests, value buffer, `Var_symbol` switch | 0.44 s | 7.3 ns | 11.3 ns |
| Nested tests, switch on head bits | 0.13 s | 2.2 ns | 5.9 ns |
| Typed trees | 0.46 s | 7.7 ns | 6.2 ns |
| Source syntax | 0.14 s | 2.3 ns | 6.2 ns |

The gain has two parts: no Match call, and no `Var_symbol` dispatch,
capture buffer, or value array.

The compiler as a generated program: `src/*.x` (56 units, 796 match
statements) translated serially. "Built with" is the lowering inside the
compiler binary; "applies" is the lowering it performs.

| Built with | Applies | Self-translation | W3 | W4 | W3, 0 functions |
| --- | --- | ---: | ---: | ---: | ---: |
| built-in | built-in (today) | 101.99 G | 4.62 M | 12.34 M | 1.41 G |
| built-in | component | 101.31 G | 4.75 M | 10.19 M | 1.41 G |
| component | built-in | 98.07 G | 4.19 M | 11.18 M | 1.32 G |
| component | component | 97.42 G | 4.33 M | 9.23 M | 1.32 G |

Correctness of the nested lowering: the 11 match fixtures with program
output pass under every variant. All 1,116 compiler fixtures give the
built-in's stdout, status, and diagnostics; only 9 C, 2 transform, and 1
emit artifact change. Unit tests pass, 946 of 946. Strict stage 1 builds
with every lib and src match lowered and regenerates all 112 src C/H files
byte for byte. In src, 943 arms become nested tests; 311 keep a Match site
(alternation, negation, interior stars, repeated binders), 4 stay dynamic,
and 68 are macro-valued cases.

## Design

The rule is `$rewrite($matched)` on the bound `(match SUBJECT ROWS)` from
`grammar.x`; the transform sends `match` to the statement rule as it sends
`switch`. The component returns `(code-value "lowered" CODE ())`, a block
of verbatim C text (a list whose head is a String, which the emitter writes
as it is) around the bound subject, cached patterns, and bodies. Lowering
steps into those nodes, and the cleanup walk sees an ordinary `switch`, its
existing `break` barrier. W3's second function, cursor name shortened:

```c
List _x2c_match_expr = form;
switch (_x2c_match_expr ? _x2c_match_expr->car.u64 : 0) {
  case <add bits>ULL: ; { List c = _x2c_match_expr;
    if (c && c->car.u64 == <add bits>ULL && (c = c->cdr, 1)) { return 1; break; } }
  case <mul bits>ULL: ; { List c = _x2c_match_expr;
    if (c && c->car.u64 == <mul bits>ULL && (c = c->cdr, 1) && c) { Var x = c->car;
      if ((c = c->cdr, 1) && c && Var_equal(c->car, _5->cdr->cdr->car)
          && (c = c->cdr, 1) && !c) { return (long) x.u64 + 1; break; } } }
  default: ; return -1; break;
}
```

The nested subset is a literal Symbol (compared by bits), `?`, a unique
`?name`, a typed capture with a literal tag other than `varray` or `vmap`,
a nested List, a final `*` or `*name`, and any other literal, compared by
`Var_equal` with the same cell of the cached pattern. Other arms keep the
emitter's text: a `MatchCaptureSite`, the dynamic entry, or
`Macro_case_capture_at`, with the capture buffer declared only for them.
Labels follow the emitter's rule, including directive groups. A List
subject is read directly; another converts in a fresh declaration.

## What the kernel keeps

- Parsing, arm binding, and typed captures, with the fields `match_types`,
  `in_pattern`, and `match_is`: they are pattern-literal parse state, and
  `parse_catch_pattern_literal` sets `in_pattern` for catch patterns. None
  of the three fields can go.
- No region row: the `switch` is the existing `$switched` barrier.
- Catch sites share no lowering with match, only the pattern parser,
  `match_pattern_binders`, `match_pattern_value`, and the Match runtime.
- The emitter's C-text arm writer goes; its generic verbatim rule stays.

Kernel services: (1) verbatim C text in lowered carriers, documented with
a fixture, including that transform and cleanup walks step into nodes
inside it; (2) `Code.pattern_value(pattern)` and `x2c_fresh_binding(role)`
with meta-helper forwarders; (3) `match` accepted by
`Code.register_rewrite`, and the transform's `<match>` arm calling the
statement rule with no fallback; (4) a lowered carrier skips
prepared-replacement analysis in `_rewrite`.

## Source cost

| Change | Lines |
| --- | ---: |
| emit.x: `$emit.match.*` templates, match section, dispatch arm | -244 |
| transform.x: `_match_cases`, `_match_records`, `matchcases` arms | -32 |
| compiler.x: `match_value_head`, `match_value_flat_head`, `_flat_capture_tag` | -52 |
| cleanup.x: `matchcases` case and `_rewrite_matchcases` | -6 |
| Kernel services 1 to 4 | about +30 |
| Component as a port of the emitter, flat arms | about +300 |
| Component with nested tests instead of flat arms | about +370 |

A port nets about -5 lines; the nested component about +65. Nested tests
in the emitter would add about 110 lines, so the capability costs about 45
fewer lines as a component. The five-variant prototype is 864 lines.

## Risks

- 796 src and 25 lib match statements change their C, so the bootstrap
  refresh rewrites most generated files. The fixpoint, strict stage 1,
  fixtures, and unit tests are the review, not the C diff.
- Editing a shipped component's meta code fails `make build` from a
  bootstrap that links the previous copy: stage 0 stages the meta helper,
  whose own source needs the stale component. Reproduced with a one-token
  change to `component-access.x`, so the defect predates this work; the
  prototype built through a kernel environment toggle. Delivery must land
  services 2 to 4 in bootstrap before the component, and each later edit
  meets the same defect until it is fixed.
- The transform re-normalizes lowered typed trees: a `(op , (op = ...) 1)`
  step lost its assignment. The cause is unknown; C text avoids it.

## Recommendation

Proceed, with the named kernel service for verbatim C text, in two moves.
First the component as a port of the emitter: it deletes about as many
kernel lines as it adds, translates at or under the built-in on W4 and
within 4 percent on W3, and keeps runtime unchanged. Then nested static
tests, judged on the runtime and self-translation numbers above. Gary
decides whether that second move's roughly 65 added lines are acceptable
under the campaign's deletion rule.

Not measured: Linux, GCC, `--source-map` output for C-text arms,
`make verify` probes, `proof-cold-collection`, stages beyond 1, and the
diagnostic for a non-List subject that does not convert.

## Design review

The component reuses the binder's form, the `switch` barrier, the Match
runtime, and the emitter's arm rules, and relies on no new kernel form.
The variant switch and the `X2C_*` toggles are scaffolding and must not
ship.
