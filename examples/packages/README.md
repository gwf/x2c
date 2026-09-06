# Creating and using packages

These examples cover creating a package, combining packages, and using each
maintained third-party adapter.

- [greet](greet/): a minimal package used by the
  [Greet example](../power/greet-client.x). This is part of `make examples`.
- [HTTP and JSON releases](http-json-releases/): an application that combines
  libcurl requests with yyjson parsing. Its local fixture test is part of
  the optional `make packages-check`.

## Package examples

Third-party examples live beside their adapters under the repository's
`packages/` directory. Follow the links below to their source and build
instructions.

| Examples | Purpose | Package instructions |
| --- | --- | --- |
| [pcre2](../../packages/pcre2/examples/) | Regular expressions and named captures | [PCRE2](../../packages/pcre2/README.md) |
| [yyjson](../../packages/yyjson/examples/) | JSON parsing and writing | [yyjson](../../packages/yyjson/README.md) |
| [libcurl](../../packages/libcurl/examples/) | HTTP requests and transfers | [libcurl](../../packages/libcurl/README.md) |
| [termbox2](../../packages/termbox2/examples/) | Interactive terminal applications | [termbox2](../../packages/termbox2/README.md) |
| [blis](../../packages/blis/examples/) | Matrix and vector computations | [BLIS](../../packages/blis/README.md) |
| [libuv](../../packages/libuv/examples/) | Event loops, processes, and networking | [libuv](../../packages/libuv/README.md) |
| [raylib](../../packages/raylib/examples/) | Images, charts, and optional windows | [raylib](../../packages/raylib/README.md) |

## Build and run

From this directory (`examples/packages`), enter the real package directory.
For example, to play Game of Life:

```sh
cd ../../packages/termbox2
make run-life-interactive
```

This builds the dependency, adapter, and application as needed, then runs the
game in your terminal. Press any key to quit. Use the package Makefile rather
than running its source directly with `x2c run`: the Makefile supplies the
package search paths, native headers, and link settings.

From the repository root, the same command is:

```sh
make -C packages/termbox2 run-life-interactive
```

Each package README lists its example commands. The first build may download
its pinned native dependency; later builds reuse the shared cache. These
examples are checked by the optional `make packages-check`, outside ordinary
`make examples`.
