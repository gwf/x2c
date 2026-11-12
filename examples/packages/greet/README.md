# greet

A minimal teaching package. `src/greet.x` defines `Greeting` with two
methods and a `repeat` function, and its Makefile builds it with
`packages/package.mk`. The
[packages chapter](../../../docs/src/guide/packages.md) walks through it, and
the [Greet example](../../power/greet-client.x) imports it.

Install the released package, then build a program that imports it:

```sh
x2c install greet
x2c build -o greeter greeter.x
```

From the repository root of a checkout, build it in place instead:

```sh
make -C examples/packages/greet build
./x2c build --package-dir examples/packages -o greeter greeter.x
```
