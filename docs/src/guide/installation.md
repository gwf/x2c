# Install a Native Compiler

Build and install x2c into a dedicated prefix from a source checkout:

```sh
make install PREFIX="$HOME/.local/x2c"
export PATH="$HOME/.local/x2c/bin:$PATH"
x2c build hello.x --output hello
./hello
```

Use the project's supported GNU Make. The install command builds the compiler
and installs its matching runtime, headers, source support, compile-time Lisp
SDK, symbols, and license. It does not require Cosmopolitan or an APE build.
With no `PREFIX`, `make install` keeps its development behavior: it installs
into the checkout's `bin/` under the current branch name.

`PREFIX` must be absolute and dedicated to x2c. Move or rename the complete
prefix to relocate it. Keep `bin`, `include`, `lib`, `src`, `etc`, and
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
System-wide merged layouts such as installing these support directories
directly into `/usr` are outside this dedicated-prefix contract. Native
executables and archives remain specific to their host platform and
architecture; relocating them does not make them cross-platform binaries.

The installed tool defaults are `cc` and `ar` from `PATH`. Explicit `--cc` and
`--ar` options take precedence, followed by `X2C_CC`/`X2C_AR`, then `CC`/`AR`,
then the defaults in `lib/x2c/toolchain`. Build identity is recorded separately
in the installation inventory, not as a path to the producer's compiler tools.

## Build, debug, and use packages

Direct source and `x2c.toml` project builds use the same installed compiler.
For source debugging, opt into native debug information and retain the
generated C:

```sh
x2c build -g --build-dir .x2c-build hello.x --output hello
lldb ./hello
```

The debugger steps through the generated `.c` files under the build
directory. Without `--build-dir` or `--save-temps`, generated objects are
removed after the build.

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
