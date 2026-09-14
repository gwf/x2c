# Install a Native Compiler

Install a release with one command, or build and install from a source
checkout. The release route needs `curl`, `tar`, and a C compiler:

```sh
curl -fsSL https://x2c-lang.dev/install.sh | sh
export PATH="$HOME/.local/x2c/bin:$PATH"
```

`X2C_PREFIX` chooses another prefix and `--version <n>` pins a release.
Running the script again upgrades the prefix and keeps installed packages.
`tools/check-install-script.sh` exercises the same script against a
release layout built from the current tree.

From a source checkout:

```sh
make install PREFIX="$HOME/.local/x2c"
export PATH="$HOME/.local/x2c/bin:$PATH"
x2c build hello.x --output hello
./hello
```

Use the project's supported GNU Make. The install command builds the compiler
and installs its matching runtime, headers, compile-time Lisp SDK, symbols,
runnable examples, an empty package directory, and license. It does not
require Cosmopolitan or an APE build. With no `PREFIX`, `make install` keeps
its development behavior: it installs into the checkout's `bin/` under the
current branch name.

## The x2c home

An installed prefix and a source checkout share one layout, the x2c home:

```text
<home>/bin/x2c           the compiler
<home>/include/          runtime sources and generated headers
<home>/lib/libx2c.a      the runtime archive
<home>/etc/              symbol snapshot and compile-time Lisp
<home>/packages/         installed packages, one directory each
<home>/examples/         runnable examples (installed prefix)
<home>/src/              compiler sources (checkout only)
```

The compiler finds its home by walking up from its own executable, then from
the current directory, to the nearest directory holding `include/` and
`etc/symbols.xlisp`. `X2C_HOME` names a home explicitly and takes precedence.
`x2c env` prints the resolved home, layout, package roots, and host tools;
`x2c env home` prints one value. Every `import` searches `<home>/packages`
after the explicit `--package-dir` and manifest directories, so a package
placed there needs no build flags.

`PREFIX` must be absolute and dedicated to x2c. Move or rename the complete
prefix to relocate it. Keep `bin`, `include`, `lib`, `etc`, `packages`, and
`licenses` together. Paths may contain spaces. Quote the compiler path when
invoking it:

```sh
"/path with spaces/x2c/bin/x2c" build hello.x --output hello
```

An upgrade stages a complete payload, replaces files owned by the previous
installation, and removes obsolete owned files using its inventory. It leaves
unrelated files alone and refuses to overwrite an unrelated file with the same
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
System-wide merged layouts such as installing these support directories
directly into `/usr` are outside this dedicated-prefix contract. Native
executables and archives remain specific to their host platform and
architecture; relocating them does not make them cross-platform binaries.

The installed tool defaults are `cc` and `ar` from `PATH`. Explicit `--cc` and
`--ar` options take precedence, followed by `X2C_CC`/`X2C_AR`, then `CC`/`AR`,
then the defaults in `lib/x2c/toolchain`. Build identity is recorded separately
in the installation inventory, not as a path to the producer's compiler tools.

## Developer workflow

A source checkout is the development install. After `make build-safe`, the
checkout is a complete home with `bin/x2c` (`make build-install` links it to
the current branch's compiler), and its own `packages/` directory. Select it
for one shell with `PATH`, or for one command with `X2C_HOME`:

```sh
export PATH="$HOME/src/x2c/bin:$PATH"
X2C_HOME="$HOME/src/x2c" x2c env
```

Keep the global prefix on a release. Install it from a tagged `main`, never
from a working branch, so a bug seen through it reproduces for every user.
Validate a release candidate in a scratch prefix and remove that prefix
afterwards. Compiler development itself runs through `make` inside the
checkout and does not depend on which compiler `PATH` selects.

## Build, debug, and use packages

Direct source and `x2c.toml` project builds use the same installed compiler.
For source debugging, opt into native debug information and original source
locations:

```sh
x2c build -g --source-map hello.x --output hello
lldb ./hello
```

On macOS this also produces `hello.dSYM`. Move that companion directory
with the executable when debugging elsewhere. Generated objects may be removed
after the build; `--build-dir` remains available when you want to retain them.

See [source mapping](../reference/cli.md) for the source-location
contract and platform debug-artifact behavior. Source mapping changes native
`__FILE__` and `__LINE__` to refer to the original x2c source.

For a [package source distribution](packages.md), unpack the source archive,
select the installed compiler, and use a dependency cache outside its prefix:

```sh
export X2C_DEPS_DIR="$HOME/.cache/x2c-dependencies"
make -C packages/yyjson prepare build X2C="$HOME/.local/x2c/bin/x2c"
x2c build --package-dir packages \
  --c-system-dir packages/yyjson/deps/include app.x --output app
```

Source package builds retain their existing producer-path restrictions; an
installed compiler path containing spaces is supported. Native dependency
preparation can download sources. Ordinary consumer builds do not install a
compiler or fetch missing native dependencies automatically.
