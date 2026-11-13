# Install a Native Compiler

Install a release with one command, or build and install from a source
checkout. Then create a first project, run it, and build it for a debugger.

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

A source build needs a GCC- or Clang-compatible C compiler, `ar`, GNU Make,
Git, and Bash. It does not need an existing x2c compiler, because the
checkout contains generated C for the bootstrap:

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

## Write a first program

These steps assume `x2c` is on `PATH`, as after the release installer or
`make install`. Start a project with
[`x2c new`](../reference/cli.md#start-a-project):

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

You can also build a single source file directly. For source debugging, add
native debug information and disable optimization:

```sh
x2c build -g -O0 src/main.x -o hello
lldb ./hello
```

Source mapping is on by default. On macOS the build also produces `hello.dSYM`;
move that directory with the executable. The build removes generated objects;
pass `--build-dir` to keep and reuse them. Bare `--save-temps` uses
`.x2c-build` for retained files. `--debug` enables compiler logging, not native
debug information. [Source mapping](../reference/cli.md#source-mapping) gives
the location rules. To use a C library through a package, see
[packages](packages.md).

## The x2c home

An installed prefix and a source checkout share one layout, the x2c home:

```text
<home>/bin/x2c           the compiler (in a checkout, the bootstrap
                         compiler until `make build-install`)
<home>/include/x2c/      runtime sources and generated headers
<home>/lib/              the runtime archive and unit interfaces
<home>/etc/              compiler prelude and runtime Lisp assets
<home>/libexec/x2c/      external commands (installed prefix)
<home>/packages/         installed packages, one directory each
<home>/examples/         runnable examples (installed prefix)
<home>/src/              language component sources (installed prefix);
                         all compiler sources (checkout)
<home>/licenses/         license files (installed prefix)
```

The compiler finds its home by walking up from its own executable, then from
the current directory, to the nearest directory holding `include/` and
`etc/compiler-prelude.x`. `X2C_HOME` sets the home explicitly and takes
precedence.
`x2c env` prints the resolved home, layout, package roots, and host tools;
`x2c env home` prints one value. Every `import` searches `<home>/packages`
after the explicit `--package-dir` and manifest directories, so a package
placed there needs no build flags.

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

## Packaging and relocation

The `PREFIX` given to `make install` must be absolute and dedicated to x2c.
Move or rename the complete prefix to relocate it. Keep `bin`, `include`,
`lib`, `libexec`, `etc`, `src`, `packages`, and `licenses` together. Paths
may contain spaces. Quote the compiler path when invoking it:

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
[C compiler and linker
options](../reference/cli.md#c-compiler-and-linker-options) gives the full
tool selection
order.

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

Clone the default branch for released source; release tags mark published
versions. A source checkout is the development install. After
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
