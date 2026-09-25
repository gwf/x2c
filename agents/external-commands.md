# Working on external commands

An external command is an ordinary x2c program in `commands/<name>/` that
the driver runs as `x2c <name>`. Read the current command and its tests
before changing its behavior. The
[completed design](../plans/archive/external-commands.md) owns the framework
decisions; the [CLI reference](../docs/src/reference/cli.md#commands)
describes what users see. A feature plan owns the command's behavior. Check
its current owner before moving a tool or adding rules to a command.

## Add or move a command

1. Put its `.x` sources and a `main` in `commands/<name>/`. Move an existing
   implementation and its tests rather than keeping a second copy in
   `tools/` or `src/`. Keep compiler services that need parser or semantic
   state in `src/`; command interaction and options belong in the command.
2. Add `name|maturity|summary` to [the manifest](../commands/manifest.txt).
   Choose `experimental` unless shipping the command is already decided.
   Both maturities build in a checkout. Only `shipped` commands are
   installed and built as command binaries by APE bootstrap. Promotion
   changes the manifest after its release and compatibility implications
   are decided.
3. Initialize the command environment with the embedded compiler identity,
   as [REPL main](../commands/repl/main.x) and
   [lint main](../commands/lint/x2c-lint.x) do. `make commands` supplies
   `x2c_embedded_identity()` and links the shared provisional compiler
   archive. Use the [compiler API](../docs/src/internals/compiler-api/index.md)
   for compiler-backed work. Do not add a private archive, another dispatch
   path, or command-specific packaging for the usual case.
4. Own `--help`, options, and exit status in the command. The driver forwards
   raw arguments after the command name, including `@` arguments, and does
   not search `PATH`. `x2c help <name>` runs the command's `--help`.

## Check the result

Put a smoke test at `commands/<name>/tests/run.sh`. Follow
[lint's fixture test](../commands/lint/tests/run.sh) for stable output and
[REPL's test](../commands/repl/tests/run.sh) for direct and dispatched
behavior. From the repository root:

```sh
make commands
builds/0/x2c help <name>
builds/0/x2c <name> --help
make commands-check
```

`make commands-check` builds every command and runs its smoke test;
`agent-pr-check` runs it.
When installation behavior changes, verify an installed prefix. Follow the root
[publication instructions](../AGENTS.md#verify-and-deliver) for the final
tree. Do not change the framework's validation targets or packaging to add
one command without a concrete need and the process approval they require.
