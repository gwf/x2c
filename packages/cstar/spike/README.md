# C* feasibility spike

Milestone 1 of
[the C* verification plan](../../../plans/x2c-cstar-verification.md).
`abs.proof.x` is an x2c program that feeds two scalar functions to the C*
symbolic executor through its `make_*` builder API, runs one x2c theorem
helper, and refuses success unless every requested function completed and
the final report has no obligations. `cstar-shim.h` declares the pinned
0.5.7 C surface the program uses; x2c cannot parse the upstream headers
directly.

`extract/` holds the annotation macros, an annotated program, its plain
baseline, a refused variant, and the extractor; `make extract` builds and
runs them against the x2c-graph development archive and needs no prover.

The plan records the measurements and the exact artifact hash. To
reproduce, unpack the pinned `cstar_darwin-aarch64.tar.xz`, clone
`cstar_examples` with submodules, run `cstarc verify tutorial/0_spec.c`
once there so its proof-library objects exist under `_verif/`, start
`cstarc server`, then:

```sh
CSTAR_HOME=/path/to/cstar CSTAR_EXAMPLES=/path/to/cstar_examples make run
```
