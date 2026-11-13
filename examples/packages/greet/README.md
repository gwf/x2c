# greet

A minimal teaching package. `src/greet.x` defines `Greeting` with two
methods and a `repeat` function, and its Makefile builds it with
`packages/package.mk`. The
[packages chapter](../../../docs/src/guide/packages.md) walks through it, and
the [Greet example](../../power/greet-client.x) imports it.

Install the released package, then run the Greet example from the
installed prefix:

```sh
x2c install greet
x2c run -q ~/.local/x2c/examples/power/greet-client.x
```

From the repository root of a checkout, build the package in place instead:

```sh
make -C examples/packages/greet build
./x2c run -q --package-dir examples/packages examples/power/greet-client.x
```
