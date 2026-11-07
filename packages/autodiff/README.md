# autodiff package

This package provides automatic differentiation written entirely in x2c. It
wraps no C library and has no native dependency. The book's
[Automatic Differentiation](../../docs/src/guide/autodiff.md) chapter
explains how to use it.

- [src/autodiff-macros.x](src/autodiff-macros.x): `$ad.dual` dual-number
  families and the `$ad.forward`, `$ad.reverse`, `$ad.checkpoint`, and
  `$ad.both` decorators. Its `meta` functions are staged for the importing
  unit on first use.
- [src/autodiff.x](src/autodiff.x): `AdTape` and `AdNode`, a runtime tape
  for code whose shape the decorators reject. It includes the macro module.

A unit reaches both through `import "autodiff" with AdTape, AdNode;`. A unit
that needs only the macros can include their module by path:

```x2c
#include "<path>/autodiff/src/autodiff-macros.x"
```

## Install

Install the source package, then build a program that imports it, such as
[examples/energy-gradient.x](examples/energy-gradient.x):

```sh
x2c install autodiff
x2c build --output energy energy-gradient.x
./energy
```

Platforms: source only; it builds on macOS and Linux.

From a checkout, run the examples against their expected output:

```sh
make -C packages/autodiff run
```

## Examples

- [examples/energy-gradient.x](examples/energy-gradient.x) generates a
  reverse-mode gradient for a function with a loop and a `continue`, and
  checks it against a central finite difference.
- [examples/autodiff.x](examples/autodiff.x) differentiates one function
  three ways: dual numbers, a forward-mode tangent function, and a
  reverse-mode gradient function.
- [examples/autodiff-fit.x](examples/autodiff-fit.x) fits a logistic growth
  model by gradient descent. Its loss integrates the model over 4000 steps,
  and `$ad.checkpoint` replays that loop in blocks of 64 steps.

`make short-example` builds `builds/example-autodiff` and `make example`
builds `builds/example-autodiff-fit`.

## Runtime tape

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

The package, its tests, and its examples are licensed under
[Apache-2.0](LICENSE).
