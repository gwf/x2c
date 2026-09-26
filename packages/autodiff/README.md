# autodiff

The book's [Automatic Differentiation](../../docs/src/guide/autodiff.md)
chapter explains how to use this package as an advanced topic.

Automatic differentiation written entirely in x2c. It wraps no C library and
has no native dependency.

- [src/autodiff.xmacro](src/autodiff.xmacro): `$ad.dual` dual-number
  families and the `$ad.forward`, `$ad.reverse`, `$ad.checkpoint`, and
  `$ad.both` decorators. A unit imports it with
  `$(import "<path>/autodiff/src/autodiff.xmacro")`; its `meta` functions
  are staged for that unit on first use.
- [src/autodiff.x](src/autodiff.x): `AdTape` and `AdNode`, a runtime tape
  for code whose shape the decorators reject. A unit reaches it through
  `import "autodiff" with AdTape, AdNode;`.

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
