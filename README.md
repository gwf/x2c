# x2c

C with batteries, without bullshit.

x2c extends C with dynamic values, collections, pattern matching, scoped
allocation, exceptions, threads, and Lisp. It compiles to C and works with
C libraries and native build tools. You can use the added features where
they help and keep ordinary C elsewhere. The
[C compatibility notes](docs/src/reference/language.md#host-preprocessing)
describe the cases that need source changes.

Two characters introduce much of the added syntax. `%` starts literals for
lists, maps, arrays, and strings: `%(list)`, `%{}`, `%[]`, and `%"text"`.
`$` inserts expressions into literals and introduces compile-time Lisp.
These forms let you combine C code, structured data, and code generation
in the same program.

The compiler and runtime are written in x2c. Their source shows how the
language is used in a substantial program, including how Lisp and macros
help implement the compiler. You can study it, change it, and rebuild the
language yourself.

## Start here

The [book](docs/src/index.md) covers the language, standard library, and
compiler internals. The [examples](examples/README.md) provide runnable
introductions, and [packages](packages/README.md) add optional C libraries.

1. The website landing page is the short introduction and includes the
   installation instructions. [Building the
   compiler](docs/src/internals/building.md) covers the self-host stages
   behind them.
2. The language guide covers [values and `Var`](docs/src/guide/values.md),
   [protocols](docs/src/guide/protocols.md),
   [compile-time macros](docs/src/guide/macros.md),
   [symbols and atoms](docs/src/guide/symbols.md),
   [collections](docs/src/guide/collections.md),
   [pattern matching](docs/src/guide/match.md),
   [iteration](docs/src/guide/iteration.md),
   [scopes and lifetime](docs/src/guide/memory.md),
   [contexts and threads](docs/src/guide/contexts-and-threads.md),
   [exceptions](docs/src/guide/exceptions.md), and
   [idioms](docs/src/guide/idioms.md).
3. [Language reference](docs/src/reference/language.md) and
   [compiler options](docs/src/reference/cli.md) - implemented syntax with its
   stated limitations, and every command-line flag.
4. [Standard library overview](docs/src/library/overview.md) - values and
   operations. [Architecture](docs/src/internals/architecture.md) and the
   [implementation map](docs/src/internals/implementation-map.md) explain how a
   `.x` file becomes C and where each feature is implemented.

## Build and run

You need a GCC- or Clang-compatible C compiler, an archiver (`ar`), GNU Make,
and Python 3. From the repository directory:

```sh
make build-safe
./x2c run examples/foreach.x
```

After the build, `./x2c` runs the working compiler through the repository
link. `run` compiles and runs the example in one step. Try another file from the
[example guide](examples/README.md) the same way.

To keep an executable:

```sh
./x2c build examples/foreach.x
./a.out
```

Use `--output foreach` if you want to choose its name. For help:

```sh
./x2c --help
./x2c help build
```

The [command-line guide](docs/src/reference/cli.md) covers translation to C,
build options, and integration with your own build system. [Building the
compiler](docs/src/internals/building.md) explains self-hosting and repository
checks.

## For fun: a portable bootstrap

The Cosmopolitan executable is an experiment for fun only: a minimal compiler
bootstrap, not a substitute for the full repository. It omits the examples,
book, and optional packages. Use the full repository for normal development.
See the [experiment's instructions](etc/cosmopolitan/README.md) to try it.

## Repository map

- `src/` - the translator and native compiler driver.
- `lib/` - runtime values, collections, matching, iteration, IO, contexts,
  native threads, scopes, dispatch, and diagnostics support.
- `unittest/` - the executable unit harness and compiler phase fixtures.
- `bootstrap/` - generated C sources used to build the compiler from a fresh checkout.
- `builds/` - staged self-hosted toolchains; stage 0 drives development.
- `docs/` - the user-facing book: language guide, reference, library, and
  compiler internals.
- `agents/` - agent-facing documentation (philosophy, workflow, style,
  debugging, generated inventory) and project skills in `agents/skills/`.
- `plans/` - active plans and archived execution logs.
- `examples/` - runnable language examples, larger programs, and the language shootout.
- `packages/` - optional adapters for third-party C libraries.
- `site/` - the public pages, rendered with the book by
  `make site-build`.

## Working on the compiler

The [architecture](docs/src/internals/architecture.md) and
[build guide](docs/src/internals/building.md) explain the compiler and its
self-hosting stages. Change the `.x` sources rather than generated bootstrap
C. The [development guide](agents/x2c-development-guide.md) covers repository
builds, tests, and generated files; [AGENTS.md](AGENTS.md) contains instructions
for coding agents. The current contribution policy is in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Project status

x2c is experimental and actively developed. It compiles itself four times and
compares the generated C and headers each time. Runtime tests and compiler
fixtures check behavior and generated output. The [language reference](docs/src/reference/language.md)
documents supported behavior and known limitations.

## The deal

The canonical project site is [x2c-lang.dev](https://x2c-lang.dev/).
The source is available under the [Apache License 2.0](LICENSE). You can fork
it. You do not get support, a roadmap, a release schedule, a vote on the
design, or a Discord.

I develop x2c according to my own priorities. File a bug if you like; I read
them and fix the ones that interest me. The project is not accepting external
code
contributions - see [CONTRIBUTING.md](CONTRIBUTING.md) - so you are better off
forking.

See [THIRD_PARTY.md](THIRD_PARTY.md) for the current license inventory and
notices. x2c is founder-led under the authority described in
[GOVERNANCE.md](GOVERNANCE.md); the [trademark](TRADEMARKS.md),
[security](SECURITY.md), and [support](SUPPORT.md) policies explain
the terms for using the name, reporting vulnerabilities, and asking for help.
