---
slug: self-host
section: magic
tab: self-host
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

The compiler and runtime are written in x2c. `make stage-3` builds
successive compiler stages; `make stage-diff-all` compares their output.
`--dump-ast` and `--dump-transforms` expose the syntax along the way.
