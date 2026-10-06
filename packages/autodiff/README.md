# autodiff

The book's [Automatic Differentiation](../../docs/src/guide/autodiff.md)
chapter explains how to use this package as an advanced topic.

Automatic differentiation written entirely in x2c. It wraps no C library and
has no native dependency.

- [src/autodiff-macros.x](src/autodiff-macros.x): `$ad.dual` dual-number
  families and the `$ad.forward`, `$ad.reverse`, `$ad.checkpoint`, and
  `$ad.both` decorators. Its `meta` functions are staged for the importing
  unit on first use.
- [src/autodiff.x](src/autodiff.x): `AdTape` and `AdNode`, a runtime tape
  for code whose shape the decorators reject. It exports the macro import.

A unit reaches both through `import "autodiff" with AdTape, AdNode;`. A unit
that needs only the macros can import them by path, as
`$(import "<path>/autodiff/src/autodiff-macros.x")`.

Each runtime computation uses one tape, including its constants. Binary
arithmetic operations and `backward` reject foreign nodes with `bad-arg` before changing
either tape. Keep the tape and its nodes alive together, and do not change a
recorded node's `tape` field.

## Checks

```sh
make -C packages/autodiff check
```

`check` runs [tests/test-autodiff.x](tests/test-autodiff.x), the translation
fixtures in [fixtures/](fixtures/) through the shared compiler fixture
runner, and the examples against
[examples/expected/](examples/expected/). `make fixtures-update` rewrites the
fixture expectations. `make benchmark` builds
[benchmarks/autodiff-checkpoint.x](benchmarks/autodiff-checkpoint.x), which
measures tape memory and time of the reverse-mode variants.
