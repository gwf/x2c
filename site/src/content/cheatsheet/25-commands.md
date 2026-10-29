---
title: The command line
group: Toolbox
---

```sh
x2c run main.x -- args       # build and run; reused when nothing changed
x2c build -o app main.x      # a native executable
x2c translate main.x         # emit C; --dump-ast and --dump-transforms look inside
x2c script tool.x            # cached script execution
x2c new demo                 # a project with x2c.toml and src/
x2c test                     # build and run the project's tests
x2c repl                     # a REPL that compiles your functions
x2c lsp                      # language server for your editor
x2c install pcre2            # packages from the index
x2c bind --package foo --header foo.h -l foo   # a package skeleton from a C header
x2c --help                   # the rest
```

- `x2c.toml` declares targets and their sources; `x2c run` and
  `x2c build` without a file use it.
- Every command accepts `--help`. `x2c env` shows the installation and the
  prelude in use.
