# Bootstrap C

The compiler and runtime are written in x2c, so a fresh machine needs an x2c
compiler before it can build them. This directory holds that starting point:
portable C for the runtime (`lib/`) and the compiler (`src/`), emitted by an
earlier verified stage-0 compiler.

The C here is generated. `make bootstrap-refresh` rewrites it from the
current stage 0; do not edit it by hand. `make build-safe` compiles it into
the bootstrap compiler, which then builds stage 0 from the `.x` sources.

[Building the compiler](../docs/src/internals/building.md#why-a-bootstrap-exists)
describes the chain from this C to the self-hosted stages.
