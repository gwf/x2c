---
layout: ../layouts/MarkdownLayout.astro
title: Install and Run
index: get x2c
deck: >-
  x2c is a source distribution. A working checkout needs a C compiler and
  make, and nothing else: x2c links no library outside libc and libm. On
  macOS, the command-line developer tools provide both.
description: >-
  Install x2c from the single portable file or from a source checkout, then
  translate, build, and run your first program.
jump:
  - href: "#one-portable-file"
    label: one file
  - href: "#a-fresh-checkout"
    label: checkout
  - href: "#your-first-program"
    label: first program
  - href: "#an-external-build"
    label: external build
  - href: "#if-the-build-fails"
    label: trouble
---

## One portable file

The optional x2c APE release is both a runnable bootstrap compiler and a ZIP
containing its matching x2c source distribution. It needs no checkout and no
network access:

```sh
./x2c.com bootstrap --prefix "$HOME/.local/x2c"
"$HOME/.local/x2c/bin/x2c" --version
```

The seed verifies and extracts its sources, headers, symbol inputs, and
licenses. It then asks the local `cc` and `ar` to build `lib/libx2c.a` and
`bin/x2c`. The installed compiler is an ordinary executable made for the
current host, not another Cosmopolitan executable. It uses that installed
runtime for later complete builds.

A GCC- or Clang-compatible C compiler and a compatible archiver must
already be available. Use `--cc` or `--ar` to select non-default tools. The
initial supported boundary is macOS and Unix-like GCC/Clang hosts; native
Windows remains unclaimed pending its own end-to-end release proof.

Release maintainers can build the file from a checkout with:

```sh
make ape-build
```

The first run downloads the checksum-pinned Cosmopolitan input and
prepares a shared toolchain cache. Later runs reuse it and write
`dist/x2c.com` directly.

## A fresh checkout

From the repository root:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
```

`make build-safe` builds a working x2c compiler and runtime from the portable C
included with the repository. Its output is deliberately captured because a
fresh build is verbose; a successful command prints nothing to your terminal.

The compiler you use is now:

```text
builds/0/x2c
```

After the first time, the ordinary build is simply `make`. That is the default
target, and it rebuilds only what changed.

Run the checked example programs to verify the complete translate, C compile,
link, and execution path:

```sh
make examples
```

The final line reports the number of runnable and build-only examples. It must
report no failures.

`make examples` also builds the executable tour. Run it:

```sh
./examples/build/docs-tour/docs-tour
```

```text
dynamic=42 language=x2c
build/42/fast
values=3 name=x2c
beta=2
doubled=(2 4 6 8)
match=ready 42
lisp=(x2c has lisp)
```

That program is ordinary x2c: dynamic values, interpolation, heterogeneous
collections, file iteration, a lambda, pattern matching, scoped lifetime, and
an embedded Lisp evaluator.

## Your first program

Save this as `hello.x` in the repository root:

```x2c
int main(void) {
  String name = %"x2c";
  List numbers = %(1 2 3 4);
  Var total = numbers.foldl(0, %!(sum, item) => sum + item);
  printf("%s\n", %"hello, $name; total=${total.integer()}");
  return 0;
}
```

Most of this is C. The additions are deliberately visible:

- `String`, `List`, and `Var` come from the x2c runtime.
- The compiler loads that runtime prelude implicitly for every `.x` file.
- `%"..."` is an interpolated String.
- `%(...)` is a heterogeneous immutable List.
- `%!(...) => ...` is an expression lambda.
- `numbers.foldl(...)` is method syntax selected from `numbers`' static type.

The compiler driver translates, compiles, links the matching runtime, and
runs the program:

```sh
./builds/0/x2c run hello.x
```

The driver reports translation, native compilation, linking, and the final
artifact on standard error, then marks the point where the program begins.
The program itself still owns standard output:

```text
hello, x2c; total=10
```

Use `--plain` for stable newline-delimited receipts, `--quiet` to suppress
successful build reporting, or `--verbose` to see the exact host-tool
commands. Redirected output is plain by default.

Use `build --output` when you want to retain the executable:

```sh
./builds/0/x2c build --output /tmp/x2c-hello-app hello.x
/tmp/x2c-hello-app
```

## An external build

An external C or Make build can own native compilation. In that workflow,
`translate --out-dir` names an existing generated-C directory:

```sh
mkdir -p /tmp/x2c-hello
./builds/0/x2c translate --out-dir /tmp/x2c-hello hello.x
```

The translator writes:

```text
/tmp/x2c-hello/hello.c
/tmp/x2c-hello/hello.h
/tmp/x2c-hello/hello.d
```

Generated files keep the input basename. `--out-dir` does not name one output
file. The `.d` dependency file is written by default; `--no-deps` omits it.

Compile the generated C with the runtime:

```sh
cc -iquote include /tmp/x2c-hello/hello.c \
  builds/0/libx2c.a -lm -o /tmp/x2c-hello/hello
/tmp/x2c-hello/hello
```

The second command is an ordinary C link. You can combine generated objects
with C objects, headers, libraries, and build systems you already use.

Four things to remember:

1. The standard library is implicit in every `.x` translation unit.
2. Use `run` for one build-and-launch step or `build --output` to retain the
   native artifact.
3. Use `translate --out-dir` when an external build owns C compilation.
4. Keep using C wherever C already expresses the job well.

## If the build fails

Read the end of `debug/bootstrap.log` first. The usual cause is a missing or
incomplete C toolchain.

The self-host stages, bootstrap compiler, generated headers, and tracked
artifact workflow are explained in [Building the
Compiler](../docs/internals/building.html). None of them is required to start
writing x2c.

Next: [x2c in fifteen minutes](../intro/).
