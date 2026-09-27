# Rebuild and inspect x2c

These are repository-root commands for separate build and installation tasks.
Run them deliberately; they are not part of the ordinary examples check.

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
