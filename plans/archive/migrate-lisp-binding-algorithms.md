# Author native Lisp binding algorithms in x2c

> Status: done
> 2026-09-20: delivered by the commit archiving this plan.
> Algorithms are x2c; thin wrappers retain per-unit binding registries.

## Implementation

Move signature normalization, syntax construction, group filtering and
registration checks into ordinary x2c. Generate the existing Lisp artifact
through the shared generator and existing bootstrap refresh. Keep the current
lazy/import loading boundary and public dotted entry points. Pass registry
state explicitly into algorithms; preserve recording order, query order,
source-order installation, repeatable installation, and sealing before
statement construction. Keep the signature source authoritative in declared
compiler prototypes, and preserve all existing diagnostics and rest targets.

One agent implements the algorithms, an independent reviewer checks behavior,
and root owns state wrappers, generation, integration, and publication.

## Validation

Reuse native-binding fixtures and Lisp unit tests. Add only coverage for
uncovered state-isolation or ordering behavior. Compare baseline generated
C/H and six interleaved translation measurements with equivalent cold homes,
covering binding consumers, whole library, and whole compiler. Runtime Lisp
initialization must stay unchanged. Review concrete performance costs before
accepting a new slowdown. Run the existing final-tree publication gate and
verify stage-2 regeneration before delivery to dev.

## Plan review

Compiler queries establish native types, names, and source expressions.
The port consumes those facts without new validation; deliberate literal-name,
duplicate, unknown-group, and sealed-group errors remain at their current
boundary. Thin wrappers retain state identity/lifetime; x2c functions receive
values and return syntax or replacement rows. The existing lowerer and
artifact generator own compilation. No new evaluator, cache, state API,
diagnostics, or recurring gate is introduced.

## Outcome and evidence

Six native-binding fixtures preserve generated output and diagnostics. The
Lisp suite passes 60 tests / 557 assertions. The CLI probe now checks identical
group/name pairs in two translation units, repeated installation, and two
runtime sessions. Review found an existing cold-preload bug: importing native
signature helpers could define registries in the shared parent. Initialization
now occurs at the existing per-unit macro-installation boundary in
`src/macros.x`; importing the generated support is stateless.

Six interleaved measured pairs after two warmups use the same compiler,
separate cold homes, and equivalent inputs. Both sides include the registry
initialization fix; the baseline retains the original handwritten algorithms.
The uncorrected cold baseline fails before it can translate binding consumers.
All 188 generated C/header files are byte-identical across the five workloads.
Direct equality for constant type spellings avoids unnecessary matcher work.

| Translation workload | Lisp median ms | x2c median ms | Change |
| --- | ---: | ---: | ---: |
| cold | 216.886 | 216.308 | -0.27% |
| bindings | 180.302 | 179.301 | -0.56% |
| lisp | 417.501 | 421.556 | +0.97% |
| library | 2195.442 | 2188.141 | -0.33% |
| compiler | 3023.617 | 3005.469 | -0.60% |

The binding-heavy runtime module costs about 4 ms / 1%; the whole-library
and whole-compiler medians decrease slightly. This continues Gary's accepted
small-cost migration direction; it is not a runtime execution slowdown.

Remaining Lisp owners are evaluator forms and native bindings in
`init-core`, deferred native adapters in `builtin-core` and
`lisp-bindings-core`, compiler SDK/rest/diagnostic adapters, runtime binding
declarations (`lisp-values`, `lisp-io`), and optional runtime Lisp examples
(`lisp-extras`). Generated artifacts remain Lisp by design. Var-tags remains
parked under its separate measured acceptance condition. No new publication
gate or compiler state API was introduced.
