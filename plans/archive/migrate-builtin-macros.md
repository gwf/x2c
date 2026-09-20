# Author built-in macro algorithms in x2c

> Status: done
> Completed 2026-09-20; delivered with this migration commit.
> Scope, foreach, and class generation use the shared artifact generator.

## Implementation

Keep the compiler-only built-in macro load point after the compile-time runtime
and SDK. Author algorithms as ordinary x2c, lower them during bootstrap refresh,
and ship their generated Lisp at the existing path. Preserve public entry
names, recipe timing, ASTs, evaluation order, diagnostics, and compiler queries.
Retain only primitive aliases and necessary entry adapters in the core.

Root owns scope, generator, bootstrap integration, and delivery. Bounded agents
own foreach and class ports; independent review checks compatibility.

## Validation

First prove scope lowering and its existing arity fixture. Reuse foreach and
class fixtures, unit suites, and publication checks. Compare generated output
and six interleaved baseline/port timings for cold translation, representative
consumers, whole library, and compiler. Keep runtime initialization unchanged.
Accept no new measurable slowdown without a decision on its concrete cost.
Verify regeneration through the self-hosted compiler is stable, then deliver
the final validated tree to dev. No release or site deployment is included.

## Plan review

Existing compiler queries own type, protocol, binding, layout, and diagnostics.
The port consumes those facts and constructs the same canonical ASTs with
literal templates. Shared generation replaces handwritten algorithms; it adds
no evaluator, state API, cache, validation layer, or recurring gate. Existing
bootstrap regeneration includes the new derived output at the same step.

## Implementation result

All three algorithm groups now live in one ordinary x2c source. The core
retains delayed native forwarding and public entry aliases, preserving the
existing load order. The generator assembles both artifacts through the
existing bootstrap-refresh step. Runtime Lisp initialization is unchanged.

Independent review covered the authored source and loader boundary. Focused
checks cover all 20 existing class/foreach/scope fixtures, plus strengthened
three-output cursor selection and missing protocol adoption. Baseline and
candidate generate identical C/H for a 64-field class, cursor signatures,
all 114 library outputs, and all 68 compiler outputs.

Six interleaved pairs after two warmups, identical compiler and cold homes:

| Translation workload | Baseline median | Port median |
| --- | ---: | ---: |
| Cold dispatch | 210.962 ms | 209.915 ms |
| 64-field class | 270.456 ms | 277.822 ms |
| Cursor fixture | 184.554 ms | 188.554 ms |
| Whole library | 2262.432 ms | 2276.501 ms |
| Whole compiler | 3151.594 ms | 3194.019 ms |

The first procedural foreach port slowed compiler translation about 6%.
Replacing stateful output loops with List.map and a small recursive signature
check reduced that to 1.3%, with overlapping run ranges. Class/cursor cases
remain consistently slower by 2.7%/2.2%. Gary accepted these measured costs.
Raw local evidence is in debug/builtins-timing.json and the attribution log.
The baseline is 8a5b156d.

Remaining handwritten owners are compiler/runtime execution adapters,
evaluator macros, native binding declarations/tables, literal/rest adapters,
and unit-state wrappers. The binding-generator algorithms in
etc/lisp-bindings.xlisp remain a separate candidate; var-tags retains its
separate measured acceptance condition. Runtime Lisp examples stay supported.

Publication checks passed: 930 unit tests, 747 compiler fixtures, self-hosting,
and 70 documentation samples. Stage-2 regeneration leaves both Lisp artifacts
unchanged. Final publication includes this acceptance and archive metadata.
