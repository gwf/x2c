# Install a Native Compiler

Install a release with one command, or build and install from a source
checkout. Then create a first project, run it, and build it for a debugger.
Notes for upgrading existing code are at the
[end of this chapter](#upgrading-existing-code).

## Supported platforms

| System | Architectures | Install |
| --- | --- | --- |
| macOS 15 or later | arm64, x86_64 | release or source |
| Linux with glibc 2.38 or later | x86_64, aarch64 | release or source |
| Windows through WSL2 | as for Linux | release or source |
| Windows through MSYS2 | x86_64 | source only |

Ubuntu 24.04 and Debian 13 meet the Linux requirement. Every route needs a
C compiler named `cc`: clang 15 or later, or gcc. On macOS,
`xcode-select --install` provides one. Native executables and archives run
only on the platform and architecture that built them.

## Install a release

The release installer needs `curl`, `tar`, `shasum` or `sha256sum`, and
`cc`:

```sh
curl -fsSL https://x2c-lang.dev/install.sh | sh
export PATH="$HOME/.local/x2c/bin:$PATH"
x2c --version
```

Add the `export` line to your shell startup file to keep `x2c` on `PATH`.
`X2C_PREFIX` or `--prefix <dir>` chooses another prefix, and `--version <n>`
pins a release; pass options to the script with `sh -s --`. The current
version comes from `https://x2c-lang.dev/x2c-version.txt`. Releases publish
the compiler for macOS and Linux on arm64 and x86_64, and every release's
downloads stay available.

To upgrade, run the installer again. It replaces the compiler in the same
prefix and keeps installed packages.

To uninstall, remove the prefix directory and the `export` line from your
shell startup file. Removing the prefix also removes the packages installed
in it:

```sh
rm -rf "$HOME/.local/x2c"
```

## Build from source

A source build needs a C compiler, `ar`, GNU Make, Git, and `/bin/bash`. It
does not need an existing x2c compiler, because the checkout contains
generated C for the bootstrap:

```sh
git clone https://github.com/gwf/x2c.git
cd x2c
make build-safe
make commands
./x2c --version
```

`make build-safe` builds the compiler as `./x2c`. `make commands` builds the
external commands it runs, such as `x2c new`, `x2c test`, `x2c lint`,
`x2c lsp`, and `x2c repl`. The checkout is then a complete x2c home; the
[developer workflow](#developer-workflow) explains using it in place.

To install into a prefix instead:

```sh
make install PREFIX="$HOME/.local/x2c"
export PATH="$HOME/.local/x2c/bin:$PATH"
```

The install command builds the compiler and its commands, then installs the
compiler, the shipped commands under `libexec/x2c/`, and the matching
runtime, headers, compiler prelude, runtime Lisp assets, unit interfaces
written by the installed compiler, runnable examples, an empty package
directory, and license. [Building the compiler](../internals/building.md)
describes the build in detail.

## The x2c home

An installed prefix and a source checkout share one layout, the x2c home:

```text
<home>/bin/x2c           the compiler
<home>/include/x2c/      runtime sources and generated headers
<home>/lib/              the runtime archive and unit interfaces
<home>/etc/              compiler prelude and runtime Lisp assets
<home>/libexec/x2c/      external commands (installed prefix)
<home>/packages/         installed packages, one directory each
<home>/examples/         runnable examples (installed prefix)
<home>/src/              language component sources (installed prefix);
                         all compiler sources (checkout)
```

The compiler finds its home by walking up from its own executable, then from
the current directory, to the nearest directory holding `include/` and
`etc/compiler-prelude.x`. `X2C_HOME` sets the home explicitly and takes
precedence.
`x2c env` prints the resolved home, layout, package roots, and host tools;
`x2c env home` prints one value. Every `import` searches `<home>/packages`
after the explicit `--package-dir` and manifest directories, so a package
placed there needs no build flags.

`PREFIX` must be absolute and dedicated to x2c. Move or rename the complete
prefix to relocate it. Keep `bin`, `include`, `lib`, `libexec`, `etc`, `src`,
`packages`, and `licenses` together. Paths may contain spaces. Quote the
compiler path when invoking it:

```sh
"/path with spaces/x2c/bin/x2c" build src/main.x -o hello
```

An upgrade stages a complete payload, replaces files owned by the previous
installation, and removes obsolete owned files using its inventory. It leaves
unrelated files alone and does not overwrite an unrelated file with the same
name. Publication replaces individual files; do not run an installation while
programs are compiling against it. Keep `.x2c-install-manifest` with the prefix
so upgrades retain ownership and build identity information.

For a packaging staging directory, use `DESTDIR` with the intended prefix:

```sh
make install PREFIX=/opt/x2c DESTDIR="$PWD/staging"
```

This writes `staging/opt/x2c`. Move that complete directory to its destination;
the staging path is not embedded in the compiler's runtime configuration.
`make dist PREFIX=/opt/x2c` stages the same installation under `dist/` and
writes `dist/x2c-<version>-<platform>.tar.gz` with a `.sha256` beside it.

`make uninstall PREFIX="$HOME/.local/x2c"` removes every file the inventory
owns and any directory that becomes empty. Packages installed under
`<prefix>/packages` are not owned by the compiler inventory: an upgrade keeps
them, and an uninstall leaves the prefix in place when they remain.
Installing these support directories directly into a shared tree such as
`/usr` is not supported.

An installed prefix records `cc` and `ar` in `lib/x2c/toolchain`;
[Environment](../reference/cli.md#environment) gives the full tool selection
order.

## Write a first program

Start a project with [`x2c new`](../reference/cli.md#start-a-project):

```sh
x2c new hello
cd hello
```

The project holds `x2c.toml`, `.gitignore`, and one source file,
`src/main.x`:

```x2c
/*  main.x -- greet the name given on the command line */

#include <stdio.h>

int main(int argc, char **argv) {
  String name = argc > 1 ? argv[1] : "world";
  puts(%"Hello, $name!");
  return 0;
}
```

`x2c run` builds the project and runs it. `-q` omits the build report, and
`--` starts the program's arguments:

```sh
x2c run -q
x2c run -q -- Ada
```

```text
Hello, world!
Hello, Ada!
```

Direct source and `x2c.toml` project builds use the same compiler.
For source debugging, opt into native debug information and original source
locations:

```sh
x2c build -g --source-map -O0 src/main.x -o hello
lldb ./hello
```

On macOS this also produces `hello.dSYM`; move that directory with the
executable. The build removes generated objects; pass `--build-dir` to keep
and reuse them. Bare `--save-temps` uses `.x2c-build` for retained files.
`--debug` enables compiler logging, not native debug information.
[Source mapping](../reference/cli.md#source-mapping) gives the
location rules. To use a C library through a package, see
[packages](packages.md).

## Compile C against the x2c runtime

A C program can call x2c code through the generated header. Point `-I` at the
include root and write the runtime header as `<x2c/x2c.h>`, so every system
header still resolves to the C library:

```c
#include <string.h>        /* the C library */
#include <x2c/x2c.h>       /* the x2c runtime */
```

```sh
cc app.c -I "$HOME/.local/x2c/include" \
  "$HOME/.local/x2c/lib/libx2c.a" -pthread -lm -o app
```

To compile C generated by `x2c translate` by hand, see
[external builds](../reference/cli.md#dependencies-and-external-builds). To
build a package from a source archive, see [packages](packages.md).

## Windows

Use WSL2. Inside an Ubuntu 24.04 or newer distribution the Linux release
installs with the same command. The installer needs `curl` and a `cc`
(clang 15 or newer, or gcc); `make` is needed only for a source checkout or
package builds:

```sh
sudo apt-get install -y clang make curl
curl -fsSL https://x2c-lang.dev/install.sh | sh
```

Keep the prefix and your projects on the Linux filesystem, under your WSL
home, because builds under `/mnt/c` are slower. Use clang
15 or newer, or `gcc`: Ubuntu 22.04 ships clang 14, which rejects two static
initializers in the runtime.

A source checkout also builds under MSYS2 with its `gcc`, given three
settings: check the repository out with LF line endings
(`git config core.autocrlf false`), enable native symlinks
(`export MSYS=winsymlinks:native`, which needs Developer Mode or an
administrator shell), and select the compiler with `CC=gcc X2C_CC=gcc`.
`make build-safe` then produces a working compiler. Native Windows without a
POSIX layer is not supported, and under MSYS2 only a source build is
supported.

## Developer workflow

The `dev` branch is the everyday integration branch; `main` is reserved for
releases. A source checkout is the development install. After
`make build-safe` and `make commands`, the checkout is a complete home with
its own `packages/` directory, and `./x2c` runs the checkout's compiler with
its commands. `bin/x2c` starts as the bootstrap compiler, so run
`make build-install` before putting `bin/` on `PATH`. It links `bin/x2c` to a
copy of the current compiler and copies its shipped commands into
`libexec/x2c/`. A compiler in the checkout's `bin/` links
`builds/0/libx2c.a`, the runtime built with the headers in `include/x2c`.
Select the checkout for one shell with `PATH`, or for one command with
`X2C_HOME`:

```sh
export PATH="$HOME/src/x2c/bin:$PATH"
X2C_HOME="$HOME/src/x2c" x2c env
```

Keep the global prefix on a release, so a problem seen through it reproduces
for other users. Compiler development itself runs through `make` inside the
checkout and does not depend on which compiler `PATH` selects.

## Upgrading existing code

### Upgrading from 0.15.x

Code written for 0.15.x needs these changes:

| 0.15.x | Now |
| --- | --- |
| `%<<a b>>` | `%<a b>` |
| an object or function named `expand` | another name |
| `$let(place, value) { ... }` | `with (place = value) { ... }` |
| `with expr as name { ... }` | `{ alias expr as name; ... }` |
| `Scope.retain()` | `Scope.open()` |
| `Scope.release()` | `Scope.close()` |
| `array.find(value)` | `array.index(value)` |
| `array.indexof(value)` | `array.index(value)` |
| `text.try_long(&value)` | `text.try_long(value)` |
| `Symbol.try_new(text, &symbol)` | `Symbol.try_new(text, symbol)` |
| `x2c_normalize_slice(&start, &stop, 1, n)` | `x2c_normalize_slice(start, stop, 1, n)` |
| `pattern.format(values)` | `pattern.format(@values)` |
| `logger.info(<app>, fields)` | `logger.info(<app>, @fields)` |
| `statement.bind(values)` in sqlite | `statement.bind(@values)` |

`array.find` now takes a predicate and returns the first accepted element
as a `Var`, or `void` when none is accepted. `try_double` changes as
`try_long` does. A bare List passed to `format`, a Logger method, or `bind`
is now one value, so splice the List with `@` to keep the 0.15.x meaning.
Array search changes C prototypes, so rebuild native code that calls
`Array_find` or `Array_indexof`.

`SymbolSet` literals now use single angles, and `%<<a b>>` is an invalid
token. An unescaped `>` closes the literal, so write a member that contains
`>` as a quoted String, as in `%<">" ">=">`. `expand` is a keyword alias
that maps rows over a macro, so rename an object or function that used that
name; a `Type.expand` method is unaffected.

`Scope.open` and `Scope.close` keep the old nested-region behavior and `void`
return types. Keep each open paired with one close, normally through `defer`.
In native C, rename `Scope_retain` to `Scope_open` and `Scope_release` to
`Scope_close`. Apply these changes only to Scope: `Pool.retain`,
`Pool.release`, and `Pool.up` keep their existing contracts.

`Scope.up` has no replacement field. Revise code that used it to use public
Scope operations. The public Scope layout has changed; regenerate C and
rebuild native libraries, extensions, and object files that use Scope against
matching compiler/runtime headers. See the
[Scope API](../library/modules/scope.md).

The compiler no longer evaluates Lisp. Move a compile-time Lisp form into a
`meta` function and call that function with `$`:

<!-- ignore: a 0.15.x compile-time Lisp form that the compiler now rejects. -->
```x2c,ignore
int answer = $(* 6 7);
```

```x2c
meta static int product(int a, int b) => a * b;

int answer = $product(6, 7);
```

A `.xlisp` file that `$(import "file.xlisp")` loaded becomes a `.x` file of
`meta` functions, which the unit reaches with `#include`. Runtime `Lisp`
sessions and their `.xlisp` files are unchanged.

The `$switch` decorator is removed. Give each case run of an ordinary
`switch` its own block and `break`:

<!-- ignore: the 0.15.x $switch decorator, which this release removes. -->
```x2c,ignore
$switch(code)
{
  case 1:
  case 2:
    String shared = "low";
    reached = shared;
  default:
    reached = "other";
}
```

```x2c
~int code = 2;
~String reached = NULL;
switch (code) {
  case 1:
  case 2: {
    String shared = "low";
    reached = shared;
    break;
  }
  default:
    reached = "other";
}
```

A declaration prefixed by an object-like attribute macro, such as
`#define WEAK __attribute__((weak))`, now keeps the attribute in its unit's
generated C, so a `WEAK` definition is weak.

`x2c lsp` replaces `x2c editor`. Rebuild and reinstall the VS Code
extension from `etc/vsc-extension`; it starts `x2c lsp` and needs VS Code
1.82 or newer. Replace the removed `x2c.semantic.workerPath` setting with
`x2c.semantic.compilerPath`.

An upgrade removes `x2c repl` from the prefix. The native library
playground is available only in a source checkout: run `make commands`,
then `./x2c repl`. See [Library Playground](repl.md).

#### Long-double hashes

On x87 targets, `Var` identity, content hashing, and total ordering for boxed
`long double` values now use the ten value bytes and ignore six padding bytes.
This preserves precision, signed-zero identity, and NaN payload distinctions.
The box layout is unchanged. Other long-double formats keep their native
payload width.

Recompute any stored or precomputed hashes of affected values when upgrading.
Rebuild indexes that reuse those hashes from the original values. See
[Var.wide_hash](../library/modules/var.md#Var.wide_hash) and
[Var.wide_equal](../library/modules/var.md#Var.wide_equal).

#### Using cooperative task batches

`Task.run` runs Channel jobs cooperatively on one native thread. See
[Run Channel jobs on one native
thread](contexts-and-threads.md#run-channel-jobs-on-one-native-thread).

### Upgrading from 0.14.0

Version 0.15.0 reads package native arguments from `<name>.native.rsp` instead
of `<name>.link`. The installer keeps existing packages, so rebuild source
packages and replace old native bundles with bundles built for 0.15.0.

The SQLite package calls its prepared-statement type `Prepared` instead of
`Statement`; change imports and typed variables, and use `Var.prepared` in
place of `Var.statement`. Automatic differentiation moved from the runtime
to the optional `autodiff` package.
Build or install that package and use `import "autodiff"` for its runtime types
and macros.

The removed `List.pool_*` operations now belong to `Pool`. The removed
`List.reduce`, `Array.reduce`, and `Iter.reduce` operations have no matching
method; use `Iter.foldl` when an explicit seed fits. Use `Var.truth` in place
of `Var.truthy`. `FileReadStatus` is a `Symbol`: compare a raw read's status
with `<data>`, `<eof>`, and `<error>` in place of `FILE_READ_DATA`,
`FILE_READ_EOF`, and `FILE_READ_ERROR`.
