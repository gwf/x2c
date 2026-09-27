# Dual macro values: phase 2 validation

Status: isolated validation results; completeness limits below. No production feature, commit or
publication. Baseline: `1b23aaa7e103461c3b219b9e10546aeb35384b60`.
The specification is [dual-use-syntax-templates.md](dual-use-syntax-templates.md).

## Meaning of the forms

| Reference | Read the value | Apply the value |
| --- | --- | --- |
| Named global/imported macro | `$sum` | `$sum(a, b)` |
| Ordinary variable declared `Macro sum` | `sum` | `sum(a, b)` |

The dollar sign selects the named macro namespace. Parentheses apply the
selected value. `Macro` is a type name: capitalization itself has no parser
meaning. In a Match case, the application recognizes code rather than building
it. Macro parameters retain their existing dollar-prefixed references inside
the body; lexical context and declarations distinguish those references.

Applying a macro value to code values produces code data. Inserting that result
into a program is still the ordinary compiler's job. A runtime program cannot
execute a value call today and thereby change its already compiled source.
The source notation must describe the stage, not imply runtime expansion.

Named Expression calls inside meta functions need a compatibility decision.
An earlier isolated parser experiment routed them to deferred construction;
the baseline expands them while compiling the meta function itself. Existing
helper computations may rely on that behavior. The conservative implementation
preserves existing named Expression expansion and uses an explicit Macro value
call when building code data. An alternative uses established code argument or
result context to select construction; it needs focused compatibility evidence.
Changing every named Expression call solely because `meta_body` is true is
not established as safe by these probes. The final `parser3.patch` removes that
change: named `$sum(3, 4)` inside a meta int function computes 7 as before,
while a Macro value call constructs code whose ordinary insertion evaluates
to 7. Both assertions pass in the combined prototype.

Existing local macros already have calls without a dollar sign. They retain
their existing resolution rules. Existing `(name)(arguments)` calls escape to
ordinary function calls, and bare names still provide ordinary function values.
The proposal does not reinterpret all unprefixed names as macros.

## Independently reproduced evidence

The root combined the parser and Match patches in the managed isolated
checkout `/Users/gary/.codex/worktrees/dual-values-validation/x2c`, starting at
the exact baseline above. Root production sources remain unchanged.

| Question | Executed evidence | Current limit |
| --- | --- | --- |
| Existing dollar/name distinction | Global named macro, local macro and same-name function yield 3, 23 and 103 respectively; bare function references and parenthesized calls preserve ordinary behavior | Baseline behavior, not the complete new parser |
| Bare `$sum` and calls through Macro parameters | Modified compiler produces inspectable canonical macro definition and body; native helper inspects it and constructs addition | Initial helper handles Expression slots; category breadth still under test |
| Descriptor-selected source Match | Same source case accepts runtime-selected addition and rejects runtime-selected multiplication; full Expr captures are published | Category interface is fixed, body is dynamic |
| Anonymous values | Single-terminator anonymous literal creates a Macro; native meta factory, relay, return, application and ordinary insertion execute correctly | Arbitrary scalar and noncallee captures not established |
| Composition | Actual anonymous body `(inner($left, $right))` captures a Macro parameter, recognizes parenthesized addition and reconstructs executable result 7 | Macro callee capture only; general fresh declarations still need existing expansion adapter |
| Multi-step transformation | Match a composed addition template, reconstruct addition, apply an anonymous increment template, return for ordinary binding; `(3 + 4)` becomes code evaluating to 8 | Deliberately changes behavior; not an optimizer equivalence claim |
| One body for construction and recognition | Real x2c core covers arithmetic, repeated holes, empty/nonempty sequences, composition, alpha comparison and joint relocation | Body and scope maps supplied explicitly |
| Actual source-derived repeated/sequence/Name slots | Repeated hole agrees/mismatches; empty and three-element Expr sequences reconstruct; member Name captures/reconstructs | General Name role correlation remains |
| Type and Statement adapter attempt | Type reconstructs and matches its producer-shaped result; direct return matches | Guessed Type subject differs from canonical producer shape; reconstructed singleton Statement seq is not normalized consistently; category fixture exits 1 |
| Corrected category probe | Actual source `sizeof(int)` capture recognizes; Type/Name reconstruct and recognize; Statement recognizes after explicit singleton-sequence projection | Projection is manual in this test; automatic category adapter is still required |
| Contextual Match retry | Actual Match engine rejects a wrong surrounding reference and retries correctly for repeated values, final spans and interior spans | Scope maps supplied explicitly |
| Later declaration correspondence | Existing `!and` checkpoint after capturing the later local checks earlier hole occurrences, rejects the first partition and retries successfully | Canonical data fixture, not executable forward local code; checkpoint generation still required |
| Existing Match compatibility | 28 existing Match tests pass, 220 assertions, with default relation policy | Other Match suites and performance not measured |
| Native helper domains | Actual captured program IDs change from helper54/price106 to helper56/price111; helper bytes and mtime remain unchanged; reconstructed program passes | Explicit captured-code hydration, not automatic anonymous capture registration |
| Actual Macro values through native helper | `$with_helper` body is inspected, relayed, transformed, matched and dynamically applied; local helper129 becomes132 with unchanged helper; executable assertions pass | Caller explicitly selects the callee role to transform; this is not proof of automatic definition-site hydration |

Evidence and reproducible inputs are retained under
`.context/dual-macro-phase2/`: `core.x`, `core.md`, `relation.x`,
`relation.patch`, `parser3.patch`, `parser-complete3.x`, and `transport/`.
The runtime patches are experiments, not a proposed production diff.

Root verification logs in the isolated combined checkout:

- `debug/phase2-baseline-build.log`
- `debug/phase2-combined-build.log`
- `debug/phase2-parser-root.log`
- `debug/phase2-parser2-build.log`
- `debug/phase2-complete-root.log`
- `debug/phase2-parser3-build.log`
- `debug/phase2-complete3-root.log`
- `debug/phase2-multi-root.log`
- `debug/phase2-categories-root.log` (retained prototype failure)
- `debug/phase2-categories3-root.log` (corrected producer/projection tests pass)
- `debug/phase2-relation-root.log`
- `debug/phase2-match-default.log`

The transport runners create independent scratch caches and assert helper
hashes, timestamps, changed binding IDs and executable results. Run them with
the modified isolated compiler path; the ordinary baseline cannot parse the
new Macro references in the second runner.

## Completeness boundary

The simpler surface does not require the earlier getter, contextual keyword,
methods or prefixed public APIs. Compiler lowering still needs private shared
operations; the prototypes temporarily place these in their test source so
they can be examined independently.

The current evidence does not yet establish automatic ownership/scope
discovery, complete typed slot projection, arbitrary anonymous source captures,
general dynamically selected source argument categories, or every ordinary
binding roundtrip. These remain specific integration work, with the main
specification's alternatives retained. A failed helper or parser probe rejects
that implementation, not first-class dual-purpose macros.

The Type test still uses `*type` because the existing producer represents its
type projection as a token-list splice. A single logical `Type $type` parameter
must be publishable as one Type capture (`?type`) without exposing that detail.
Keep logical parameters separate from their internal span/projection captures.
Likewise Statement wrapper projection should be internal, rather than require
the caller to select a singleton element manually. These are remaining shared
capture-interface adapters, not reasons for new user-facing operations.

The executed multi-step transformation uses the proposed forms directly:

```x2c
meta static List transform_code(Macro addition, List code) {
  Macro wrapped = lexical_wrap(addition);
  Macro increment = macro Expression(Expr $value) => $value + 1;
  match (code) {
    case wrapped(?left, ?right): return increment(addition(left, right));
  }
  return code;
}
macro Expression $transformed(Expr $code) => $transform_code($sum, $code);
```

`lexical_wrap` returns an anonymous macro whose body is
`(addition($left, $right))`. Recognition produces the actual code for 3 and 4;
the next two calls build `3 + 4` and then `(3 + 4) + 1`. Ordinary insertion,
binding and compilation produce 8. The transform itself does not inspect AST
fields. The executable fixture is `.context/dual-macro-phase2/multi-step.x`.

For dynamic argument grammar, two viable choices remain. Macro values can
accept already captured code values as ordinary arguments; this supports meta
composition without asking a runtime value how to parse source. Alternatively,
the compiler can retain a statically known parameter-category interface and
permit raw source arguments when that interface is available. Runtime selection
between macros with different category interfaces cannot determine an earlier
parse. That stage constraint is real; it does not require another getter or
public method. Selection between different bodies with one interface is a
separate test and should work.

For complete hygiene, reuse the descriptor's existing fresh and capture rows
and producer-owned binding identities, expose only missing scope/role facts,
and derive recognition checkpoints from them. Supplied maps prove the relation
and substitution algorithms; they are not a substitute for compiler extraction.
Correlated Name projections must preserve the difference between declaration,
reference and member roles rather than replacing every projection with one
undifferentiated capture.

One concrete failed implementation treated the multiplication operator `*`
as a Match wildcard. Addition therefore incorrectly matched the product
descriptor. Quoting the fixed operator role repaired that prototype, and the
dynamic addition/product counterexample now passes. This is evidence for
role-aware pattern derivation, not a need for different public notation or an
independent pattern definition. The generic prototype walker still does not
establish complete role coverage for every AST form.

For lexical anonymous composition, capture the current whole Macro List value
when evaluating the anonymous literal, store it in the existing capture
environment, and install it in the nested invocation's stored-definition
position. Do not turn the helper parameter's binding ID into a program
reference. The child's free references retain their own domain requirements.
Recognition can inline the structural child body or match the invocation at
the chosen stage; neither operation runs arbitrary helper computation backward.
The isolated direct-callee implementation uses binding identities as capture
environment keys and consumes the helper-local callee before ordinary program
binding. Cross-review found that its capture type classification still looks
up the variable name, and bare noncallee uses are not handled. Production must
retain the producer's captured type/identity and define those other roles;
this implementation cannot establish arbitrary lexical value capture.

Matching a retained invocation and matching its expanded body are distinct
operations. The lexical prototype retains an inspectable `tpl-call` in its
body and inlines it for construction/recognition. It does not yet demonstrate
source cases that select retained-invocation recognition independently of body
recognition. The compiler must retain the stage and use the corresponding
canonical view; matching must not trigger arbitrary helper computations.

No full self-host feature validation, performance measurement, cross-platform
helper validation, REPL lifetime study or production migration was attempted.

The category failure has two distinct causes. The guessed `sizeof` subject
omits the canonical declaration/parentheses structure used by the macro
producer. The Statement adapter unwraps the pattern's singleton `seq` but
leaves the reconstructed subject wrapped. Fix the producer/category view on
both sides, or use an explicit root-category alternative for direct and
singleton-sequence forms. Do not erase arbitrary nested scope structure.
This failed adapter does not reject Type or Statement templates; independent
helper tests already transport/reconstruct actual Type/Name/Statement captures.
Root independently reran the corrected category probe successfully, including
an actual source Type capture. The Statement correction in that test explicitly
selects the singleton element, so it proves the category projection rather
than automatic source-case normalization.
