# External commands

> Status: active.
> Gary approved this design on 2026-09-24. It is the only source of truth
> for how external commands are built, found, run, tested, and shipped.
> Work on any command follows it; nothing is implemented yet. Until phase 1
> lands, a command under development is a standalone program with no
> compiler dispatch.

## Goal

Some parts of x2c are best developed and delivered as separate programs
that the `x2c` driver runs, as Git runs `git-<name>` programs. They change
at their own pace, stay out of the self-hosted compiler and its bootstrap,
and give experiments on the product a place that is not the mainline
compiler. The first three are `lint`, `repl`, and `graph`.

## Terms

- A **command** is anything `x2c <name>` runs.
- A **built-in command** is compiled into the `x2c` binary: `translate`,
  `build`, `run`, `new`, `script`, `bootstrap`, `env`, `install`,
  `remove`, `list`, and `help`. The current `repl` is also built in until
  phase 3. These are the core pipeline and whatever must work with no
  other file present.
- An **external command** is a separate program named `x2c-<name>` that
  the driver runs for `x2c <name>`. Interactive, analytical, and
  experimental commands are external.
- `tools/` keeps its meaning: internal programs for building and
  maintaining the repository, never shipped. "Module" means a runtime or
  library `.x` unit, and "extension" is reserved for user-compiled code
  loaded for compile-time computation. Neither names this category.

## Decisions

These are decided; a change to one needs Gary.

1. **Layout.** Each external command lives in `commands/<name>/` as
   ordinary `.x` sources with a `main`. `commands/manifest.txt` lists
   every command, one row each: `name|maturity|summary`.
2. **Maturity.** A command is `shipped` or `experimental`. Both build and
   test in the repository and run through `x2c <name>` in a checkout.
   Only shipped commands are installed and released. Promotion is a
   manifest change.
3. **Static linking.** Each command links statically against
   `libx2c-dev.a`, the compiler's objects without `main.o`, and the
   runtime, the way the compiler itself links: the whole runtime, with
   `-rdynamic` on Linux, so a native module loaded by a command resolves
   runtime calls as it does in `x2c`. Release size is not a constraint.
4. **The compiler library.** `make commands` builds
   `builds/0/libx2c-dev.a` once for all commands. Commands include
   `src/*.x` for declarations, as `tools/x2c-graph` does today. The
   interface they may use is the provisional compiler API under
   `docs/src/internals/compiler-api/`; it is not installed and not stable,
   which is why commands ship in lockstep with the compiler.
5. **Where commands live.** The driver looks in one directory, reported by
   `x2c env libexec`: `<home>/libexec/x2c/` in an installed home and
   `builds/0/libexec/` in a checkout, resolved with the rest of the home
   layout in `src/utils.x`. It does not search `PATH`.
6. **Dispatch.** The driver recognizes a direct `argv[1]` command name
   before `cli_parse` expands response files or parses options. Built-in
   names, global options, and a response file used to supply a built-in
   command keep their current parser path. Otherwise, when
   `<libexec>/x2c-<name>` exists, the driver `exec`s it with the remaining
   raw `argv` unchanged, including `@` arguments, so the command owns the
   terminal, signals, and exit status. The driver sets `X2C_HOME`, `X2C`
   (its own executable), and `X2C_IDENTITY` (its compiler identity). An
   unknown name keeps today's error.
7. **One identity.** `x2c_compiler_identity()` hashes the running
   executable, so a command would otherwise have an identity of its own.
   `make commands` embeds the identity of the `x2c` built with it, read
   with `x2c env identity`. Command startup supplies that embedded value to
   environment initialization in place of the command executable's hash;
   ordinary compiler startup still hashes its own executable. The current
   initializer unconditionally writes the hash, so setting the embedded
   value before calling it would lose the value. Every command then reports
   the compiler's identity, which keeps interface caches and native module
   stamps shared with `x2c`. When `X2C_IDENTITY` is set and differs from
   the embedded identity, the command exits with an error that names both. Run
   directly, without the driver, a command runs normally, so standalone use
   and development need no driver.
8. **Help.** `x2c help` lists external commands after the built-in ones,
   with summaries from `<libexec>/commands.txt`. Phase 1 stages the checkout
   manifest there; phase 2 installs the shipped rows there.
   `x2c help <name>` and `x2c <name> --help` run `x2c-<name> --help`.
9. **Outside the bootstrap.** Commands are built by the stage compiler
   after `make build`. A command change never touches `bootstrap/` and
   never needs the self-host comparison.
10. **Gating.** `make commands-check` builds every command and runs each
    one's smoke tests in `commands/<name>/tests/`. It is optional in phases
    1 and 2. Starting in phase 3, `agent-pr-check` runs the shipped-command
    subset; experimental command tests remain optional, including lint's.
    Before adding that recurring check, measure it against the compiler
    build and self-host work removed by moving the REPL out of `src/`.
    If that does not offset comparable cost, keep the new check optional
    until a separate process change is agreed.

## Phases

Each phase is one delivery to `dev`. Phases 1 and 2 must land before the
REPL moves, because today's releases ship the REPL inside `x2c`.

1. **Mechanism, with `graph` as its first command.** Add `commands/`, the
   manifest, `make commands` with the `libx2c-dev.a` target,
   `make commands-check`, the libexec layout and `x2c env libexec`,
   `x2c env identity`, the embedded identity and its check, dispatch, and
   help. Stage `commands.txt` in `builds/0/libexec/`. Move
   `tools/x2c-graph` to `commands/graph` as an experimental command; its
   private archive rule goes, and its `ast-parity` test becomes its smoke
   test. Add the
   category to the repo map in `AGENTS.md` and a "Commands" section to the
   CLI reference.
2. **Packaging.** `etc/x2c-payload.x` installs shipped commands into
   `<home>/libexec/x2c/` with `commands.txt`, and `make dist` carries
   them. At this phase `graph` is experimental, so an installed home has no
   external executable yet. The APE support payload carries `commands/`,
   and `x2c bootstrap` builds shipped commands after the compiler, from
   the same objects. Release workflow changes follow
   `agents/releasing.md` and need Gary's release authorization.
3. **`repl`.** [REPL command](repl-command.md) holds the detailed plan:
   the REPL's three source files move to `commands/repl` as a shipped
   command, the compiler keeps the session services the REPL calls, and
   the compiler loses its REPL command, options, and help.
4. **`lint`.** Lint is built first as a standalone `x2c-lint` in
   `tools/x2c-lint/`, with its own build like `tools/x2c-graph`. When it
   is ready and phase 1 has landed, it moves to `commands/lint` as an
   experimental command and gains dispatch and help from phase 1 without
   changes of its own. Its machine-readable output is a command option.
   Promotion to shipped is a later decision.

Phase 4 can land any time after phase 1.

## Guidance for command work before phase 1

- Build the command as a standalone program, linked the way
  `tools/x2c-graph/Makefile` links today.
- Do not add compiler dispatch, a libexec directory, another
  `libx2c-dev` target, or packaging. Those belong to phases 1 and 2.
- Keep sources ready to move: `.x` files with a `main`, and tests that
  run the program by path.

## Validation

- Phase 1: `x2c graph` runs through dispatch in a checkout; an `@` argument
  reaches it unchanged; built-in response files retain their behavior;
  `x2c help` lists it from the staged manifest; a mismatched
  `X2C_IDENTITY` fails with both identities named; a directly run command
  reports the embedded compiler identity. Run `make commands-check`
  explicitly; it is not yet in `agent-pr-check`.
- Phase 2: `make install PREFIX=...` and `make dist` produce
  `libexec/x2c/commands.txt` with shipped rows only and no experimental
  `x2c-graph`; an APE bootstrap produces the same layout. Installed
  command dispatch is checked when the first shipped command lands.
- Phase 3: the REPL's existing probes and spike tests pass through
  `x2c repl` both in a checkout and from an installed prefix;
  `bootstrap/` no longer contains `repl*.c`. Record the gate-cost comparison
  before adding the shipped-command subset to `agent-pr-check`.
- Phase 4: `x2c lint` runs through dispatch with the lint session's
  tests as its smoke tests.

## Plan review

- **Trusted facts.** The compiler identity, the home layout, and the
  compiler objects already exist and are produced by the current build.
  Commands reuse them; the only new check is the identity comparison,
  which protects against a command linked to a different compiler reading
  its data wrongly. Embedding the compiler's identity replaces nothing; it
  corrects a command's identity, which would otherwise hash the command.
- **Reuse and new machinery.** The library archive already exists inside
  `tools/x2c-graph/Makefile`; phase 1 moves it to one shared target. New
  mechanisms are dispatch, the libexec directory, the manifest, and the
  maturity column. Each is needed because the driver must find, list, and
  ship programs it does not contain.
- **Idiom.** Commands are ordinary x2c programs built by the ordinary
  toolchain. Dispatch precedes the existing CLI parser in `src/main.x`,
  preserving the parser for built-ins and raw arguments for external
  programs.
- **Diagnostics.** One new error: the identity mismatch. Unknown commands
  keep the current error. No other validators.
