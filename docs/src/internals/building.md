# Building the Compiler

Language users can skip this chapter. It describes how the self-hosting
repository builds itself and what a contributor is expected to rebuild.

A source checkout needs a GCC- or Clang-compatible C compiler, `ar`,
GNU Make, Python 3, and `/bin/bash`. Python runs repository build tooling; it
is not a dependency of installed x2c programs or the portable executable's native
bootstrap command.

## Check build prerequisites

From the repository root:

```sh
./configure
```

This reports missing core build tools together, with installation guidance.
It checks the selected `CC` and `AR`, and `X2C_CC` when set. It does not
compile anything or write a configuration file. `make configure` runs the
same report. `make build` and `make build-safe` run it automatically before
bootstrap work or cleaning.

For optional packages, use `./configure --packages`, or name only the ones
you intend to build, such as `./configure --packages termbox2`. See the
[package instructions](../../../packages/README.md) for native dependencies.
These reports check command availability and required OpenSSL Perl modules;
upstream configure scripts and compilers still check platform support.

## Why a bootstrap exists

The compiler and runtime are written in x2c. A fresh machine cannot translate
those `.x` sources until an x2c compiler already exists. The repository
therefore carries portable C emitted by an earlier verified compiler.

The chain is:

```text
tracked portable C
  -> bootstrap compiler
  -> stage 0 compiler and runtime
  -> self-host stages 1, 2, and 3
```

`make build-safe` builds through stage 0. Language users stop there.
`builds/0/x2c` is the current development compiler; `bin/x2c` is the bootstrap
compiler until stage 0 is installed over it.

## Why later stages exist

The self-host stages translate the same compiler repeatedly. A stable compiler
makes stages 1 through 3 emit identical C and headers. The repository uses that
agreement to catch compiler regressions. You do not need it to run your own
programs.

## Generated and tracked boundaries

- Runtime and compiler behavior is written in `.x` sources.
- Numbered build directories are generated and untracked.
- The runtime aggregator is generated from the runtime module set.
- Portable bootstrap C and symbol artifacts are generated tracked outputs.

Do not hand-edit generated C or the runtime aggregator.

Contributor instructions cover when to regenerate the bootstrap snapshot and
which checks to run; see [Contributor checks](#contributor-checks).

## Symbol and native-binding artifacts

The tracked symbol snapshot is one `(snapshot 3 (ENTRIES...))` data form. It
uses compact bare `Atom`s for its fixed set of structural words, case-sensitive
`String` identifiers, and the same nested `List` syntax as `%()` x2c literals.
It never emits the legal but noncanonical `<"name">` spelling; adding the
percent prefix is the only list-syntax difference. The loader reads exactly
one form and does not evaluate snapshot content.

Native `Func` bindings use canonical function `Type` `List`s, for example
`((func (("String"))) "String")`. Structural words are lowercase `Symbol`s,
identifier names are exact `String`s, and a nullary function uses the single
parameter `Type` `(void)`.

## Contributor checks

`make doc-examples` compiles the book and website samples, including the
PCRE2 import example. Prepare that optional package first with
`make -C packages/pcre2 build`; the checker uses its generated headers and
prepared dependency includes. It does not fetch dependencies itself.

For testing, style, debugging, and artifact-refresh instructions, start with
[`agents/README.md`](https://github.com/gwf/x2c/blob/main/agents/README.md).

See [Compiler Architecture](architecture.md) for the translation phases and
the [Implementation Map](implementation-map.md) for feature ownership.
