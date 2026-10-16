# Building the Compiler

Language users can skip this chapter. It describes how the self-hosting
repository builds itself and what a contributor is expected to rebuild.

A source checkout needs a GCC- or Clang-compatible C compiler, `ar`,
GNU Make, Python 3, and `/bin/bash`. Python runs repository build tooling.

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
[package instructions](https://github.com/gwf/x2c/blob/main/packages/README.md) for native dependencies.
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

`make build-safe` builds through stage 0 and links `bin/x2c` to
`bin/x2c-bootstrap`. `builds/0/x2c` is the development compiler.
`make build-install` copies it to `bin/x2c-<branch>` and links `bin/x2c`
there; see [developer workflow](../guide/installation.md#developer-workflow).
Language users stop at stage 0. `make stage-3` builds the self-host stages,
which [the self-host build](architecture.md#the-self-host-build) explains.

## Generated and tracked boundaries

- Runtime and compiler behavior is written in `.x` sources.
- Numbered build directories are generated and untracked.
- The tracked generated outputs are the portable bootstrap C under
  `bootstrap/`, the runtime aggregator `lib/x2c.x`, and what
  `make doc-generate` writes: `agents/x2c-module-catalog.md`,
  `docs/src/internals/compiler-api/`, `docs/src/library/modules/`, and
  `site/public/llms.txt` with `llms-full.txt`.

Do not hand-edit any of them; regenerate them with their targets.

## Unit interfaces and native bindings

Each translated unit writes a unit interface, `<stem>.xi`, beside its `.c`
and `.h`. A stage build leaves the runtime's interfaces under `builds/N/lib`.
A later translation replays `lib/x2c.xi` from there as its prelude only when
the same compiler wrote it; otherwise it reads `lib/x2c.x` from source once
per process. These interfaces are untracked build output;
[Compiler Architecture](architecture.md#unit-interfaces)
describes their contents and validation.

Native `Func` bindings use canonical function `Type` `List`s, for example
`((func (("String"))) "String")`. Structural words are lowercase `Symbol`s,
identifier names are exact `String`s, and a nullary function uses the single
parameter `Type` `(void)`. Ordinary adapters and Lisp bindings build the
same signature: a typedef parameter, reference target, or result keeps its
declared name, such as `("Byte")` or `(& "Byte")`.

## Contributor checks

`make doc-examples` compiles the book and website samples, including the
PCRE2 import example. Prepare that optional package first with
`make -C packages/pcre2 build`; the checker uses its generated headers and
prepared dependency includes. It does not fetch dependencies itself.

For testing, style, debugging, and bootstrap-refresh instructions, start with
[`agents/README.md`](https://github.com/gwf/x2c/blob/dev/agents/README.md).

See [Compiler Architecture](architecture.md) for the translation phases and
the [Implementation Map](implementation-map.md) for feature ownership.
