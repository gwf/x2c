# Building the Compiler

Language users can skip this chapter. It describes how the self-hosting
repository builds itself and what a contributor is expected to rebuild.

A source checkout needs a GCC- or Clang-compatible C compiler, `ar`,
GNU Make, and `/bin/bash`. Optional package preparation and contributor
checks also use Python 3.

## Check build prerequisites

From the repository root:

```sh
./configure
```

This reports missing core build tools together, with installation guidance.
It checks the selected `CC` and `AR`, and `X2C_CC` when set. It does not
compile anything or write a configuration file. `make configure` runs the
same report. In a Git checkout whose `core.hooksPath` is unset, it also sets
`core.hooksPath` to `tools/hooks` in the repository configuration, which
every worktree of the repository shares. Because the value is relative, each
worktree runs the `tools/hooks/pre-push` of its own checkout. `make build`
and `make build-safe` run `make configure` automatically before bootstrap
work or cleaning.

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
- The tracked generated outputs are:
  - the portable bootstrap C under `bootstrap/`, which
    `make bootstrap-refresh` rewrites, as do `make precommit`,
    `make agent-pr-check`, and `make sanity-check`, which run it;
  - the runtime aggregator `lib/x2c.x`, the shipped `meta` code compiled
    into the compiler, `src/linked-meta.x`, and the meta helper's compiler
    queries, `etc/meta-queries.x`, which `make build` and every target that
    depends on it rewrite when they are stale;
  - what `make doc-generate` writes: `agents/x2c-module-catalog.md`,
    `docs/src/internals/compiler-api/`, `docs/src/library/modules/`, their
    sections of `docs/src/SUMMARY.md`, and `site/public/llms.txt` with
    `llms-full.txt`;
  - `docs/src/reference/syntax/x2c.ebnf` and
    `docs/src/reference/syntax/lexical-data.md`, which
    `tools/syntax-spec write` renders from `etc/syntax/`;
  - `tools/version-viewer/snapshots.js` and its digest in the viewer's
    `index.html`, which `python3 tools/version-viewer/refresh-snapshots.py`
    rewrites.

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

## WebAssembly runtime and programs

The optional browser target uses Emscripten Memory64 (`-m64`). It keeps the
language's 64-bit `long`, pointers, and `Var` representation. Install
Emscripten and Node separately, then run from the checkout root:

```sh
make wasm-runtime
tools/wasm-build examples/tours/language.x /tmp/language
node --input-type=module -e \
  'import("file:///tmp/language.js").then(m => m.default())'
```

`make wasm-runtime` builds stage zero, compiles its generated runtime C, and
writes `builds/wasm/libx2c.a`. `tools/wasm-build` translates one `.x` file
and links the whole archive directly with Emscripten. It writes an ES module
loader (`.js`) and a `.wasm` file beside the requested output stem. The
native runtime archive is never passed to this link. Neither command is
part of `make check`; the manual check workflow has an optional wasm job.

The build defaults to `emcc`, `emar`, signed characters, size optimization,
and Emscripten longjmp support. `WASM_CC`, `WASM_AR`, and `WASM_CFLAGS`
override the corresponding build settings. `tools/wasm-build` also accepts
whitespace-separated linker options in `WASM_LDFLAGS`, without evaluating
shell syntax. Retain `-m64` and `-sSUPPORT_LONGJMP=emscripten` when changing
compiler flags. The loader supports browsers, workers, and Node; Node must
support Memory64 and ES modules. Node 26 can load the generated `.js`
module directly as shown above.

Programs use a temporary in-memory filesystem. Source files and host data
are not copied into it automatically. For example, the exceptions gallery
sample requires its fixtures at the same virtual path:

```sh
WASM_LDFLAGS='--embed-file examples/data/power-exceptions' \
  tools/wasm-build examples/power/exceptions.x /tmp/exceptions
```

Program memory starts at 64 MB and can grow to 256 MB; the stack is 4 MB.
Threads, process execution, native TCP sockets, and HTTP servers are
unsupported in this single-threaded browser build. `Job`, `File.popen`,
`Thread`, `Channel`, `Dispatch`, and pool workers cannot provide their native
behavior. In-memory HTTP parsing, routing, and response construction remain
available. Browser execution requires Memory64;
check the playground's support notice before running a program.

## Contributor checks

`make doc-examples` compiles the book and website samples, including the
PCRE2 import example. Prepare that optional package first with
`make -C packages/pcre2 build`; the checker uses its generated headers and
prepared dependency includes. It does not fetch dependencies itself.

For testing, style, debugging, and bootstrap-refresh instructions, start with
[`agents/README.md`](https://github.com/gwf/x2c/blob/dev/agents/README.md).

See [Compiler Architecture](architecture.md) for the translation phases and
the [Implementation Map](implementation-map.md) for feature ownership.
