# Runtime headers for C compilers

`make build` fills `include/x2c/` with symbolic links: the runtime `.x`
sources from [lib/](../lib/README.md) and the `.h` headers that stage 0
generates from them in `builds/0/lib`. Only this README, the Makefile, and
`.gitignore` are tracked.

Compile translated C against a checkout with `cc -iquote include/x2c`. An
installed compiler keeps the same layout under `<home>/include/x2c/`. The
[architecture chapter](../docs/src/internals/architecture.md) describes the
repository's generated directories, and
[building the compiler](../docs/src/internals/building.md) describes the
stages that produce the headers.
