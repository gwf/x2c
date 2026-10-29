---
slug: self-host
section: magic
tab: self-host
title: The compiler is written in itself. Change it.
---

```sh
# Build normally, or rebuild from the checked-in bootstrap C.
make build
make build-safe

# Let the compiler build successive versions of itself.
make stage-3
make bootstrap-refresh       # Refresh the checked-in bootstrap C.
make stage-diff-all    # Compare generated C and headers.

# Inspect parsed syntax and the compiler's transformations.
./x2c translate --dump-ast examples/foreach.x
./x2c translate --dump-transforms examples/foreach.x
```

The compiler is x2c. The runtime is x2c. The language server, the test
runner, and the HTTP library are x2c. `make stage-3` has the compiler build
itself three times over to prove the output converges, and `--dump-ast`
shows you the syntax at every step.

Follow an idea far enough and you change the tool you are thinking with, in
the language you are already using. No committee required.
