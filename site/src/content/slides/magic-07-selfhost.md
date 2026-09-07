---
section: magic
tab: self-host
---

```sh
# Build normally, or rebuild from the checked-in bootstrap C.
make build
make safely

# Let the compiler build successive versions of itself.
make stresstest
make rebootstrap       # Refresh the checked-in bootstrap C.
make stage-diff-all    # Compare generated C and headers.

# Inspect parsed syntax and the compiler's transformations.
./x2c translate --dump-ast examples/foreach.x
./x2c translate --dump-transforms examples/foreach.x

# For fun: build the experimental portable bootstrap.
make ape-build
./dist/x2c.com bootstrap --prefix ~/.local/x2c
```

The compiler and runtime are written in x2c. `make stresstest` builds
successive compiler stages; `make stage-diff-all` compares their output.
`--dump-ast` and `--dump-transforms` expose the syntax along the way.
The Cosmopolitan executable is an experiment for fun only. It carries enough
source to bootstrap a native compiler and runtime, but no examples, book, or
optional packages. Use the full repository for normal development.
