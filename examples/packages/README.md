# Creating and using packages

These examples cover creating a package, combining packages, and using each
maintained third-party adapter.

- [greet](greet/): a minimal package used by the
  [Greet example](../power/greet-client.x). This is part of `make examples`.
- [HTTP and JSON releases](http-json-releases/): an application that combines
  libcurl requests with yyjson parsing. Its local fixture test is part of
  the optional `make packages-check`.

## Package examples

The following directories are relative symbolic links to the examples kept
beside each adapter. They provide another way to browse the same source;
there are no copied examples. Build and run them through the package's own
Makefile, using the commands in its README.

| Examples | Purpose | Package instructions |
| --- | --- | --- |
| [pcre2](pcre2/) | Regular expressions and named captures | [PCRE2](../../packages/pcre2/README.md) |
| [yyjson](yyjson/) | JSON parsing and writing | [yyjson](../../packages/yyjson/README.md) |
| [libcurl](libcurl/) | HTTP requests and transfers | [libcurl](../../packages/libcurl/README.md) |
| [termbox2](termbox2/) | Interactive terminal applications | [termbox2](../../packages/termbox2/README.md) |
| [blis](blis/) | Matrix and vector computations | [BLIS](../../packages/blis/README.md) |
| [libuv](libuv/) | Event loops, processes, and networking | [libuv](../../packages/libuv/README.md) |
| [raylib](raylib/) | Images, charts, and optional windows | [raylib](../../packages/raylib/README.md) |

These adapters need optional native dependencies. Their examples remain in
`make packages-check`, outside ordinary `make examples`. From the repository
root, for example:

```sh
make -C packages/pcre2 run
make -C examples/packages/http-json-releases test
```
