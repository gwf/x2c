# Package management

`x2c install`, `x2c remove`, and `x2c list` keep their legacy options, help,
and response files. The driver expands response files once and forwards
the argument vector to this command for legacy CLI parsing. `x2c package install`, `remove`, and `list` also invoke the
same operations; like other external commands, they receive literal arguments.

The command owns installed package markers, indexes, downloads, digest
checks, staging, installation locks, source-package builds, and lockfiles.
Source-package builds invoke the matching compiler through
`Compiler.driver_executable()`.

Project builds use one private operation:

```text
x2c-package ensure --lock /project/x2c.lock [--index INDEX] [--quiet] -- NAME VERSION ...
```

The project reader supplies dependency pairs in declaration order. The command
preserves locked archive choices, installs missing packages, and writes the
existing six-field lockfile. A satisfied lockfile needs no index or network.
Zero pairs remove an obsolete lockfile. Exit status is the only response;
diagnostics and receipts use standard error. This is an internal interface
between the matching driver and command, not an additional user command.

Editor requests and dry runs skip preparation. Dependency-free builds with
no lockfile do not require the package executable.

`make commands-check` runs the existing package installation probe through
`tests/run.sh`. Its temporary home lives outside `unittest/build` because the
compiler checks can clean that directory concurrently. After `make commands`,
run `sh commands/package/tests/run.sh` for just these checks.
