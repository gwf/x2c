> Status: done
> Exploration and implementation complete on 2026-09-08. The user requested
> a PR after the spike; all four cleanups are implemented on top of f68e4c8.
> Publication validation is recorded in the PR.

# Further source opportunities from x2c-graph

## Recommendation

Four small changes remove repeated compiler/runtime work and reduce authored
source by nine lines overall. They are a reasonable cleanup, but the measured
speed improvement is too small to justify a performance project by itself.
Keep this separate from the build-warning repair being done by another agent.

The observable goal is unchanged compilation and runtime behavior with less
redundant work. No language, public API, data format, or diagnostic changes.

## Discovery and temporary probes

Status: complete (2026-09-08).

`x2c-graph focus`, `compare`, `sites`, and `allocation-returns` identified the
callers and candidate operations. Source tracing established control flow;
instrumented native compilers counted actual work. Static graph edges are
not execution counts. Native sampling supplied runtime leads the parsed call
graph alone cannot rank, especially interpolation-generated String calls.

| Change | Source reason | Measured work removed |
| --- | --- | --- |
| Delete protocol lookup in `Compiler._binary_op_type` | Its only caller, `_resolve_content`, already calls `_protocol_operator_expression` and returns on success. That helper returns a List for every successful `_resolve_protocol_operator`. The fallback repeats the same lookup after a miss, with no intervening compiler mutation. | 10,162 repeated calls; zero successes. Six source lines deleted. |
| Reuse `$ast.rewrite_children` in `Type._from_ast_items` | The existing macro performs exactly this child conversion and preserves an unchanged List. Keep `_from_ast(child, context)` as the conversion. | 63,289 of 172,291 temporary Arrays avoided (36.7%). Three source lines deleted overall, including the import. |
| Queue only List children in `_expression_requires_resolution` | Scalars are currently pushed and then immediately discarded on pop. Filtering before insertion preserves the order and handling of every List. | 1,028,071 scalar pop iterations removed out of 1,862,768 total (55.2%). One source line added. |
| Pass the existing span to SymbolSet `_order_offset` | `SymbolSet.index` already reads the mask and computes span. Its helper reads and reconstructs the same value again. | One source line deleted; the optimized ARM64 lookup avoids repeated header reconstruction. |

The SymbolSet helper remains the single expression for the ordered-table
offset. Change its private signature to `(SymbolSet x, uint32_t span)`;
`index` passes `span`, and `getindex` passes `_u32(x, 8) + 1`. Do not duplicate
the layout formula or change the byte readers. For Type, use the established
relative import `$(import "../src/ast-rewrite.xmacro")`, not the absolute path
used to isolate the temporary probe.

## Measurements and checks

Status: complete (2026-09-08).

Native optimized compilers translated all 27 compiler and 46 runtime modules
using `translate -q -j 1 --no-deps`, separately for `src` and `lib`. Every
prototype and every timed run produced all 146 C/header files byte-identical
to the current stage-0 compiler. Instrumented binaries were not timed.

Three runs per individual change gave median differences of -0.26% for Type,
-0.65% for the protocol deletion, -1.17% for the resolution queue, and -1.72%
for SymbolSet. These runs overlap enough that the individual percentages
should not be treated as established speed improvements.

Six alternating-order baseline/combined pairs gave medians of 4.490 seconds
and 4.446 seconds, a 0.97% reduction. The combined prototype was faster in
five of six pairs; one initial run was slower. This is a modest local result,
not a promised improvement on other machines or user projects.

The combined compiler translated, native-compiled, and ran 20 existing
protocol/operator and macro/lambda fixtures with exact expected stdout.
Its runtime override passed the existing SymbolSet suite: six tests,
58 assertions. These are spike checks; publication still needs the ordinary
repository gate on the eventual authored and regenerated tree.

Evidence and reproducers are in `.context/graph-spike-2/`, particularly
`combined.py`, `check-combined.py`, `combined-timings.json`, the individual
probe directories, and the graph query outputs. Logs are in
`debug/graph-spike-2-*.log`. Temporary compilers live under `/tmp` or the
system temporary directory; the evidence directory contains their paths.

## Candidates not recommended

Changing the sizing pass of `String.join` from `foreach` to a direct List
loop removed iterator work, but its median improvement was only 0.66%, inside
the observed timing variation. Keep the clearer existing source. Joins are
frequent (181,483 in the measured workload), so the low direct-call count in
the source graph would have been misleading without runtime measurement.

`String.repr` had no calls in this compiler workload. `String.unescape`
already took its no-escape fast path on 99.97% of observed calls. Neither
supports a compiler optimization from this evidence.

`_function_contract_type` and Type canonicalization have different typedef
filtering behavior. Do not merge them merely because their graph shapes and
unchanged-result rates look similar.

Sampling also highlighted Var decoding and SymbolSet lookup. The graph
connects `Var.new` through `_tag2id` to `SymbolSet.index`; typed boxing often
passes a constant tag through that generic lookup. This is a useful next
research question, but no replacement has been prototyped. Any follow-up
must preserve the existing packing and descriptor implementation rather than
duplicate it in new constructors. No speed claim follows from this lead.

## Implementation

Status: complete (2026-09-08).

The four changes above form one small pull request about avoiding repeated
work, without the String loop change or Var redesign. The authored diff
reuses the existing operations and removes nine lines overall. The warning
repair already present in f68e4c8 is preserved.

1. Apply the exact expressions, Type macro reuse, and SymbolSet changes.
2. Repeat the targeted behavior checks and translation comparison. Refresh
   generated artifacts only through the repository targets.
3. Review and fix the completed authored diff for repeated checks, duplicate
   code, unnecessary mechanisms, and idiomatic x2c before publication proof.
4. Run `tools/gate-state.py ensure agent-pr-check` on the final tree, then
   publish the requested draft PR against main. Merging is not requested.

## Plan review

The earlier protocol operation establishes the miss; the proposed deletion
removes its consumer's duplicate lookup. The resolution scanner already
establishes that scalar values need no work, and filtering queue insertion
retains exactly the same semantic scan of Lists. The generated SymbolSet
header supplies a span already read by `index`; passing that local value
reuses the fact without adding stored metadata.

Type conversion reuses the existing child-rewrite macro and `_from_ast`
operation. This is an operational child traversal, not a new AST grammar
requiring another Match pattern or binding path. All existing Match handling
and canonical output construction stay in `_from_ast`.

The design deletes a lookup and a duplicate loop, uses an ordinary `foreach`
filter, and passes an existing local to a private helper. It introduces no
helper, representation, cache, traversal, validator, dedicated diagnostic,
negative fixture, or recurring check.
