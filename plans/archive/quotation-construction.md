> Status: done
> Implemented and adopted on `codex/quotation-construction-adoption`.
> Initial measured code: `3e836f926939b6e4a2652f026eaf0f4d8df40038`.
> Integrated code: `2dd6cd6fd8af2a67c04d6639aef14ac075fc3348`.
> Gary accepted the cost and authorized publication to dev on 2026-10-28.

# Ordinary quotation construction and adoption

Keep `_match_declare` entirely in source quotations. Its callers keep supplied
binding identities, types and finished children. Anonymous quotation values are
supplied at construction; retained projection work does not mean missing args.

Construct canonical syntax and splices immediately when their existing insertion
forms are available. Keep ordinary placement for free names, private identities,
source anchors, frozen fragments, effects and projections requiring it. Preserve
code-versus-data behavior, diagnostics, evaluation order and public runtime ABI.
Do not add a quotation-to-AST conversion API or another semantic implementation.

## Implementation

1. Simplify the completed quotation envelope to a tag consed onto its AST. Use
   the shared literal builder so fully constant quotations fold to cached Lists.
   Keep the established placement and emitter owners for consuming the carrier.
2. Remove redundant construction work: append with an empty tail, repeated
   insertion dispatch on complete expressions, unnecessary generated branches
   where static input types already establish the case. Review the remaining
   fallback representation against the known projection counterexamples.
3. Measure constant quotes and supplied declarations against equivalent literal
   ASTs. Separate payload construction, necessary carrier cost and projection
   overhead. Measure the readable helper too; do not compare only to the slow
   old quotation-plus-rebuild path. Fix avoidable measured costs before adoption.
4. Retain the readable match helper and remove representation selectors from
   adoption sites. Update focused fixtures and the book for the final internal
   representation and behavior. Add only focused lasting coverage that protects
   actual identity, stage, source or evaluation-order behavior.
5. Review the authored and generated diff; run focused regressions, converged
   self-host validation and the existing publication validation command for local
   adoption. The initial spike preserves the original no-publish instruction.
   Subsequent development publication follows Gary's explicit approval below.
   No recurring checks are added.

## Plan review

Existing producers establish canonical List syntax and the caller's finished
children. Existing placement owns binding, hygiene, staging, origins and effects;
existing emission trusts finished placed syntax. No consumer gains a new origin
validator or readiness walker. The work reuses typed insertion, splice and
literal-cache owners and shared declaration normalization. The completed carrier
is necessary to preserve the existing code/data distinction, but should cost one
cell over its payload. Existing projection failures retain their owning paths.
No dedicated diagnostic or recurring validation process is added. Source review
must keep the readable caller as the acceptance criterion throughout.

## Delivered result

The motivating helper now contains source quotations throughout:

```c
meta static Code _match_declare(Type type, List binding, List content) {
  Code value = content ? $!($type){ ($content) } : NULL;
  return content ? $!{ $type $binding = $value; }
                 : $!{ $type $binding; };
}
```

The callers supply expression content, so the typed quotation supplies its
annotation. The parentheses let existing typed insertion accept that content
without changing its contract. There are no AST selectors, rebuild calls or
new conversion operations in the helper. Existing users of
`Compiler.rebuild_statement` retain their contract; completed quotations return
canonical syntax through that operation without substitution or traversal.

Completed quotations cons one String tag onto their canonical AST payload.
The tag preserves code-versus-List-data behavior. Construction shares typed
quotation insertion, splice operations and the literal cache. Both constructor
paths share declaration normalization. The retained constructor remains for
placement-dependent projections, private names, source anchors and freezing.
Those records contain supplied values, not absent arguments.

The completed representation exposed an existing traversal assumption: generic
lowering entered a quotation before cleanup replaced a valid placeholder.
It converted the placeholder to an empty statement. Transform and static-region
walks now preserve the quotation boundary until its existing placement consumer.
The four existing `rewrite-try-*` regressions pass without expectation changes.
The emitter consumes completed carriers in its existing traversal and avoids
quotation tests on ordinary Symbol-headed nodes.

## Cost relative to literal ASTs

Constant quotation evaluation returns a cached pointer, exactly as a literal
AST does. A native proof verifies the quotation's tail is the literal node:

```c
static Code quoted(void) { return _37; }
static List literal(void) { return _36; }
```

The carrier costs one extra cached cell at module initialization. There is no
per-evaluation construction. The baseline already cached constant quotations;
the final implementation preserves that property after fixing an intermediate
prototype's loss of constant folding.

The native workload constructs one million warm declarations in Scope batches
of 100, with the same supplied Type, compiler-issued binding and typed child.
Apple clang 17, arm64, `-O2`; medians of seven alternating trials. Counts are
whole-process retired CPU instructions, including setup and the common loop.
Elapsed values are secondary and rounded by `/usr/bin/time -l`.

| Construction in the final executable | Instructions, billions | Seconds |
| --- | ---: | ---: |
| Literal canonical statement sequence | 3.520 | 0.14 |
| Same literal plus completed carrier | 3.793 | 0.14 |
| Quotation with supplied Type, binding and Code | 4.449 | 0.17 |
| Quotation with written `int` and supplied binding/Code | 4.240 | 0.16 |
| Quotation with written `int` and String name | 4.304 | 0.16 |
| Identical literal with carrier and String name | 4.020 | 0.16 |

The generic quotation uses 26.4% more instructions than the bare canonical
sequence, or 17.3% more than its identical carrier literal. The String-name
case adds 7.1% over its identical carrier literal. Necessary type normalization
and insertion remain; runtime decisions disappear where static input types
already establish the case.

A separate alternating baseline/candidate run measures ordinary quotation
construction at 7.728B versus 4.421B instructions: 42.8% fewer. Elapsed time is
0.30 versus 0.17 seconds. This comparison excludes rebuilding on both sides.

The readable helper itself remains more expensive than its handwritten
predecessor. Do not claim literal cost for that dynamic helper:

| One million helper calls | Instructions, billions | Seconds |
| --- | ---: | ---: |
| Original handwritten declaration, initialized | 3.787 | 0.14 |
| Readable quotation helper, initialized | 6.288 | 0.24 |
| Identical literal payload, grouping and carrier | 5.106 | 0.20 |
| Original handwritten declaration, uninitialized | 1.882 | 0.07 |
| Readable quotation helper, uninitialized | 3.041 | 0.12 |
| Identical literal payload and carrier | 2.760 | 0.10 |

The initialized helper adds 66.0% over the old bare declaration, or 23.1%
over the identical literal result. The uninitialized helper adds 61.6% and
10.2%, respectively. The bare-node comparison includes the quotation's
statement sequence, carrier and initialized expression grouping. The same-result
comparison isolates remaining construction decisions. These are native copies
of the helper, not whole-compiler or placement timings.

## Compiler measurements

Both trees were converged through bootstrap refresh and safe rebuild. Each
compiler reported a nonempty prelude and no missing prelude units. Baseline:
`f5d0eb2fbe5a501c53b67535d5e4477f18a69b06`; candidate: `3e836f926`.
No builds or other observed compiler gates ran during measurement.

Seven unchanged unit-test sources and their support files were copied to one
common input directory. They cover Match, statements, AST helpers, Lists,
Arrays, lambdas and protocols. Both compilers translated the exact same source
bytes with their own matching headers and prelude. Seven alternating warm
trials gave these medians for the complete seven-input workload:

| Tree | Retired instructions, billions | Elapsed seconds |
| --- | ---: | ---: |
| Baseline | 64.777 | 4.25 |
| Candidate | 60.773 | 4.07 |

The candidate uses 6.2% fewer instructions. The existing seven-unit compiler
translation workload also improves from 28.930B to 27.408B instructions
(1.90 to 1.81 seconds). That second workload uses each tree's corresponding
sources, including the moved Type implementation, so it is not an identical
input comparison. Neither result is a full-build timing or isolates quotation
changes from the shared Symbol and Type improvements in this batch.

## Validation, scope and recommendation

`tools/gate-state.py ensure agent-pr-check` passes the final code and generated
tree: 1,309 compiler fixtures, 1,051 runtime tests with 27,538 assertions,
bootstrap/stage comparisons, cold collection, documentation examples and command
checks. Focused cold/warm imported-helper, source-map and type-shape probes match
the baseline. The new fixture protects construction, binding identity, pointer
normalization, source placement and supplied finished children.

The authored compiler/runtime diff adds 227 lines and removes 98: net 129 lines,
excluding generated linked meta code. It consolidates insertion, declaration
normalization and Symbol decoding; it does not demonstrate overall source
reduction or remove the remaining deferred constructor.

Adopt locally for readable lowering and lower ordinary construction cost.
Constant quotations meet literal evaluation cost. Supplied quotations approach
that cost but still have measured overhead. Cold/varied construction and full
build timing were not measured. Moving every remaining placement-dependent
projection into construction was not attempted. No hygiene, resolution,
evaluation-order, staging or public-contract change is used to obtain the result.

Raw runs, benchmark sources, binary hashes and exact revisions are retained in
`/tmp/x2c-quotation-adoption/`: `final-cost.json`, `final-before-after.json`,
`final-common-inputs.json`, `final-translation-corresponding-sources.json` and
`final-revisions.json`. Gate logs are under `debug/adoption-gate.log` and
`debug/agent-pr-check/`. The initial spike stayed local and added no schedules.
The canonical checkout was not edited by this work.


## Development integration

Gary accepted the measured cost increase and explicitly authorized publication
to dev on 2026-10-28. The implementation was integrated with upstream
`fa1a917ce7da20d2a7624a942dd9e5d21910c46c`. Bootstrap conflicts were regenerated
from the merged authoritative sources. The API classification conflict retains
both upstream networking entries and the quotation entries. Review verified
that the emitter preserves upstream source mapping and held-node ordering.

The integrated code and regenerated bootstrap, `2dd6cd6fd`, pass
`tools/gate-state.py ensure agent-pr-check`: 1,313 compiler fixtures,
1,074 runtime tests with 27,708 assertions, bootstrap comparisons, documentation
and command checks. The final report-only commit retains that compiler proof
and runs the existing documentation check.

A new converged baseline at `fa1a917ce` and the integrated candidate translated
the same seven unchanged input files used above. Both reported a valid prelude
and no missing units. Seven alternating warm trials gave these medians:

| Tree | Retired instructions, billions | Elapsed seconds |
| --- | ---: | ---: |
| Current upstream | 63.634 | 4.36 |
| Integrated quotation candidate | 60.895 | 4.13 |

The candidate uses 4.3% fewer instructions on this workload. The accepted
helper construction costs remain those reported above; this measurement does
not turn the helper into a performance improvement over its handwritten AST.
Raw integration measurements and revisions are retained under
`/tmp/x2c-quotation-adoption/integration/`. The tree is validated for development
publication; no production promotion or recurring checks are part of this work.
