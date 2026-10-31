# x2c

C with batteries, without bullshit.

x2c extends C with collections, dynamic values, pattern matching, scoped
allocation, exceptions, threads, and compile-time macros written in x2c. It
compiles to C and uses ordinary C compilers and libraries. You can use the
added features where they help and keep ordinary C elsewhere.

The compiler and runtime are written in x2c. You can read their source, change
it, and rebuild the language itself.

## A small example

Save this as `hello.x`:

```x2c
int main(void) {
  Array names = ["Ada", "Grace", "Linus"];
  foreach (String name in names)
    printf("Hello, %s!\n", name);
  return 0;
}
```

Array literals and iteration work alongside ordinary C functions. The runtime
is available without an explicit include. The [language tour](examples/tours/language.x)
shows more: maps, matching, memory scopes, exceptions, and macros.

## Build and run

From a checkout, you need a GCC- or Clang-compatible C compiler, `ar`, GNU Make,
and Bash. You do not need an existing x2c compiler: the checkout
contains generated C for the bootstrap.

```sh
make build-safe
./x2c run hello.x
./x2c run hello.x -- first second
```

`run` compiles and executes the program. `--` starts the program's arguments.
To keep an executable instead:

```sh
./x2c build hello.x -o hello
./hello
```

For a ready-made program, try `./x2c run examples/foreach.x`. For installation
outside the checkout, follow the [installation guide](docs/src/guide/installation.md).
It covers release installation and building an installed compiler from source.

## What to explore

- [Examples](examples/README.md): small programs and larger applications you
  can run and modify.
- [The book](docs/src/index.md): language guide, reference, standard library,
  and compiler internals. Start with [values](docs/src/guide/values.md) and
  [idioms](docs/src/guide/idioms.md).
- [C libraries](packages/README.md): optional packages for databases, graphics,
  networking, parsing, and other native libraries.
- [Command-line reference](docs/src/reference/cli.md): compilation, projects,
  scripts, inspection, and build options. `./x2c --help` lists commands.
- [Benchmarks Game](examples/shootout/README.md): official problems with
  idiomatic and tuned x2c, plus contributed C, Python, Rust, and C++ references.

## Status and compatibility

x2c is experimental and actively developed. APIs and language details can
change. It aims to keep C useful inside a higher-level language, but it does
not accept every C preprocessing pattern unchanged. Read the
[C compatibility notes](docs/src/reference/language.md#preprocessing)
when bringing existing C source into x2c.

The [language reference](docs/src/reference/language.md) documents supported
behavior and limitations. The repository checks runtime behavior, compiler
fixtures, and self-hosted builds; those checks do not imply compatibility
with every platform or C library.

## Reading the implementation

Start with the [source guide](src/README.md). It explains the compiler's flow,
files, and module directories. Each module directory has its own guide to the
entry file and implementation members.

| Directory | What is there |
| --- | --- |
| [src/](src/README.md) | Compiler, driver, compile-time operations, and syntax lowering. |
| [lib/](docs/src/library/overview.md) | Runtime values, collections, memory, IO, concurrency, and Lisp. |
| [commands/](commands/manifest.txt) | External commands such as project creation, packages, and the REPL. |
| [examples/](examples/README.md) | Executable language examples and applications. |
| [packages/](packages/README.md) | Optional adapters for third-party C libraries. |
| [unittest/](unittest/) | Runtime tests, compiler fixtures, and focused probes. |
| [bootstrap/](bootstrap/) | Generated C used to build the first compiler. |
| [builds/](builds/) | Working compiler stages and generated build outputs. |
| [docs/](docs/src/index.md) | The book's source. |
| [site/](site/) | The public website. |

[Compiler architecture](docs/src/internals/architecture.md) explains the
phases. [Building the compiler](docs/src/internals/building.md) explains
self-hosting and the available checks. Edit the `.x` sources; regenerate
bootstrap C through the build targets.

## Short glossary

| Term | Meaning in x2c |
| --- | --- |
| **Module** | A source unit with one responsibility. It can be one file, or an entry file with members listed in a `module { ... }` block. |
| **Member** | An implementation file listed in a module block. It compiles as part of the entry's unit. See the [module visibility rules](docs/src/reference/language.md#module-blocks) for which declarations other files can use. |
| **Translation unit** | The source compiled together into one generated C source file. A module's entry and all its members form one translation unit. |
| **Component** | Here, an independent source unit in [src/components/](src/components/README.md) that implements a language feature, such as matching or exceptions. This is a repository term, not a language keyword. |
| **Package** | A named directory with an entry source file and the sources it includes. Packages expose public names under a package prefix. The adapters in [packages/](packages/README.md) wrap third-party C libraries. |
| **Include** | `#include "foo/foo.x"` makes a source unit's public declarations and compile-time definitions available. C headers use ordinary `#include` directives. |
| **Import** | `import "geo";` finds a package through configured package directories and binds an alias, so callers can write `geo.Vec`. `as` changes the alias; `with` exposes selected names directly. |
| **Runtime** | The library code used by compiled programs: collections, Strings, memory management, IO, and other facilities in `lib/`. |
| **Prelude** | Definitions made available automatically when compiling a source unit, including the standard runtime and shipped syntax rules. |
| **Bootstrap** | The checked-in generated C used to build x2c without an existing x2c compiler. Later builds use x2c to compile its own source. |

See the language reference for [module blocks](docs/src/reference/language.md#module-blocks)
and [packages and imports](docs/src/reference/language.md#packages-and-import).

## License and project policy

x2c is available under the [Apache License 2.0](LICENSE). Forks are welcome.
The project is not accepting external code contributions; see
[CONTRIBUTING.md](CONTRIBUTING.md). Development follows the author's priorities,
without a promised roadmap, release schedule, or support commitment.

See [THIRD_PARTY.md](THIRD_PARTY.md) for dependency notices,
[SECURITY.md](SECURITY.md) for vulnerability reporting, and
[SUPPORT.md](SUPPORT.md) for support policy. [GOVERNANCE.md](GOVERNANCE.md) and
[TRADEMARKS.md](TRADEMARKS.md) describe project authority and use of the name.
The project website is [x2c-lang.dev](https://x2c-lang.dev/).
