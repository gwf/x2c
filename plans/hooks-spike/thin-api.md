# The thin API

> Status: reference
> Spike on private branch `gwf/hooks-spike`, 2026-10-07. Proposed spellings
> are illustrative; existing names are cited where they exist.

## Rule

Kernel modules, library extensions, and user includes use this one API. A
feature that needs anything else justifies a new entry here or stays in the
kernel. The same component source moves from a user include to `lib/` to
`src/` unchanged; only where its meta code executes changes.

Status: **public** = available to meta code today; **internal** = exists in
the compiler but not exposed; **prototype** = on this spike branch;
**missing** = does not exist.

## 1. Registration

A component's registrations are its initializer: they run when the
component's file is included and replay through interfaces.

| Entry | Phase | Status | Used by |
| --- | --- | --- | --- |
| `keyword ALIAS $macro;` | parse: identifier statement or expression | public (macros.x:2398) | `foreach`, `class`, `loop`, `synchronized` |
| `hook switch $m;`, other C keywords | parse: C keyword statement | prototype (statements.x) | string switch; `match`, `try`, `raise`, `with` |
| `hook function $m;` | parse: function definition body | prototype (parse.x) | tracing, entry guards, lambda lowering |
| typed node hook, by node kind, may decline: `hook <switch> f;`, `hook <match> f;` | transform: after binding and typing | prototype (waves 1, 3) | string switch, collection literals, printf formats, `match`, destructuring |
| declaration-position hook through claims: `hook <TAG> f;` for `(claim TAG MESSAGE VALUE)` | bind: block declaration | prototype (wave 2) | `$auto`; later destructuring, `class` |
| reader-prefix hook | lex and parse: `$!`-style prefixes | rejected (wave 4): adds about 20 kernel lines and removes none; see reader-prefix.md | quotations stay in the kernel's macro substrate |
| fact registration: `x2c_fact_record`, `x2c_fact_lookup` | parse and collect, replayed by interfaces | prototype (wave 3) | `delegate`; later `protocol`, `class` defaults |
| member-resolution fallback: `hook <member> f;` | bind: on a resolution miss only | prototype (wave 3) | `delegate` |

## 2. Building and reading syntax

| Entry | Status | Notes |
| --- | --- | --- |
| Quotations `$!{...}`, `$!(...)`, `$!KIND{...}` | public | anonymous macros applied to the locals they name |
| List literals `%(...)` with `$x`, `@xs` | public | structural data |
| Builders `x2c_ident`, `x2c_literal_*`, `x2c_expr_*`, `x2c_stmnt_*`, `x2c_decl_make`, `x2c_param_make` | public (lib/meta.x) | |
| Function parts `x2c_function_name`, `x2c_function_parameter`, `x2c_function_body` | public (lib/meta.x) | |
| `match` over syntax in meta code | public | the pattern component's in-place client |
| Hygienic names shared across quotations: `x2c_fresh_name`, `x2c_effect_name` | prototype (wave 1) | today a declaration in one quotation cannot be named in another, which forced string switch's second layer |
| Child rewriting helper | internal (`$ast.rewrite_children`) | meta code recurses by hand |

## 3. Typing queries

| Entry | Status | Notes |
| --- | --- | --- |
| `x2c_syntax_type(expr)` | public | type of a bound expression |
| Typing queries from project meta code | prototype (wave 2) | nested query request answered at the call site; about 0.17 M instructions per query |
| `x2c_type_resolve`, `x2c_type_fields`, `x2c_type_members`, `x2c_type_is_*`, `x2c_type_element` | public (lib/meta.x) | |
| `x2c_method_resolve(type, name)` | public | member resolution, including the self type |
| `x2c_member_resolve(type, name, call)` | prototype (wave 3) | the kernel's own row: method, field, or ambiguity; no fallbacks |
| `x2c_protocol_member(participant, base, member)` | public | |
| conversion at a position: `x2c_convert(position, expr, type)` | prototype (wave 4; kernel `Compiler.convert_at`) | positions `<init>`, `<assignment>`, `<return>`, `<argument>`, `<hole>`, `<printf>`; proof `var-switch.x` |

## 4. Contributions

| Entry | Status | Notes |
| --- | --- | --- |
| Unit support, once per key: `x2c_effect_support(key, name, decl)` | prototype (wave 1); was internal (`add_support`, `$adapter.memo`; carrier `early` effect) | string switch helper, adapters, lambda helpers |
| File initialization area: `x2c_effect_initialize(area, stmt)` | prototype (wave 1); was internal (`add_init`) | areas `<protocol>`, `<prepare>`, `<statics>`, `<finish>`; statements arrive lowered |
| Include anchor: `x2c_requires(<errors>)` | internal (`needs_exception`, `_anchors`) | `try`, `raise` |
| "Never returns" fact | internal (`Ast.never_returns`) | `raise` |
| Cleanup participation: `hook <try> f;` returning `outer`, `exits`, `region`, `landing` rows | prototype (wave 4) | `try`, `finally`, `match`, static locals; ordinary `defer` in generated code is already public |
| Region-analysis effect rows | internal (regions.x table) | `$scope`, `$let` |

All contributions apply under the expansion's semantic transaction
(`SymTxn` with the pending checkpoint), so a failed expansion leaves none
behind. Ordering rule: contribute code literals before lowering and lowered
forms after it.

## 5. Facts

| Entry | Status | Used by |
| --- | --- | --- |
| Member-resolution rule (alias, fallback field) | prototype for fallbacks (wave 3); protocol aliases internal | `delegate` (done), `protocol` member aliases |
| Conversion rule (source, destination, converter) | internal (converters, `Func` conversion) | protocols, typed arrays |
| Operator member | internal (operator-ledger.x) | protocol operators (deferred) |
| Declaration defaults | internal (`Defaults`, compiler.x:885) | `class` |

## 6. Patterns

| Entry | Status | Notes |
| --- | --- | --- |
| Pattern value for meta code: `x2c_pattern_value(pattern)` | prototype (wave 3) | bound patterns hold literals as cache entries project meta code cannot read |
| Pattern to test and binders | internal (Match runtime, `match_pattern_binders`) | one compiler for `match`, `catch`, macro recognition, typed captures |
| Static pattern to nested `if` tests: `x2c_pattern_steps(pattern, subject)` returns `(STEPS BINDERS CURSORS)`, `x2c_pattern_nest(steps, inner)` makes the block | prototype in lib/meta-patterns.x (wave 5); see catch-predicate.md | clients: match-component.x (project meta, one query per arm) and the compiled-in catch selector |
| Dynamic pattern to `MatchPlan` | public runtime (lib/match.x) | |

## 7. Diagnostics

| Entry | Status | Notes |
| --- | --- | --- |
| `x2c_diagnostic_fail_at(node, category, message, notes)` | prototype (waves 1-2) | string switch label check, every component's input checks |
| `x2c_invocation_file`, `x2c_invocation_line` | public | |

## 8. Execution

| Where meta code runs | Cost per call | When |
| --- | --- | --- |
| Project meta, forked helper | about 1.3 M compiler instructions and 0.17 ms | user includes |
| Library meta, in process | about 1.5 M instructions over hand-written for `$switch` | `lib/` components |
| Compiled into the compiler (linked meta) | lowest | kernel modules (`foreach` today) |

Project meta code cannot read compiler state such as source text; it receives
what it needs as arguments.

## Missing entries, by number of clients

1. Typed node hook: 5 or more.
2. Unit support and file initialization as x2c calls: 4 or more.
3. Diagnostics at a node: every component.
4. Hygienic names shared across quotations: every quotation-built lowering.
5. Pattern to `if` tests: `match`, `catch`.
6. Fact registration at collection: `protocol`, `delegate`, `class`.
7. Declaration-position hook: 3.
8. Conversion at a position: protocols, typed lowerings.
9. Cleanup participation: `try`, `finally`, `match`, static locals.
10. Reader-prefix hook: quotations.
