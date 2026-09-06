# Rebuild and inspect x2c

These are repository-root commands for separate build and installation tasks.
Run them deliberately; they are not part of the ordinary examples check.

```sh
# Build normally, or rebuild from the checked-in bootstrap C.
make build
make safely

# Let the compiler build successive versions of itself.
make stresstest
make rebootstrap       # Refresh the checked-in bootstrap C.
make stage-diff-all    # Compare generated C and headers.

# Inspect parsed syntax and the compiler's transformations.
./builds/0/x2c translate --dump-ast examples/foreach.x
./builds/0/x2c translate --dump-transforms examples/foreach.x

# Build a portable executable that carries its own source.
make ape-build
./dist/x2c.com bootstrap --prefix ~/.local/x2c
```

The compiler and runtime are written in x2c. `make stresstest` builds
successive compiler stages; `make stage-diff-all` compares their output.
`--dump-ast` and `--dump-transforms` expose the syntax along the way.
The Cosmopolitan executable carries its source and can rebuild itself
into a native compiler and runtime.
