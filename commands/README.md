# External commands

Each directory here is an ordinary x2c program that the driver runs as
`x2c <name>`. [manifest.txt](manifest.txt) lists every command as
`name|maturity|summary`. `make commands` builds all of them into
`builds/0/libexec`; an install includes only the `shipped` ones.

- [bind](bind/README.md), [graph](graph/README.md), [lint](lint/README.md),
  and [repl](repl/README.md) build in a checkout with `make commands`;
  releases do not install them.
- `build` (build, run, and script), [lsp](lsp/README.md),
  [new](new/README.md), [package](package/README.md), and `test` ship
  with the compiler.

The [command-line reference](../docs/src/reference/cli.md#commands)
describes what users see. Each command keeps its tests in `<name>/tests/`.
