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
  `remove`, `list`, and `help`. These are the core pipeline and whatever
  must work with no other file present.
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
   runtime. Release size is not a constraint.
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
6. **Dispatch.** `x2c <name> args...` checks the built-in table first.
   Otherwise, when `<libexec>/x2c-<name>` exists, the driver `exec`s it
   with the remaining arguments unchanged, so the command owns the
   terminal, signals, and exit status. The driver sets `X2C_HOME`, `X2C`
   (its own executable), and `X2C_IDENTITY` (its compiler identity). An
   unknown name keeps today's error.
7. **Lockstep.** When `X2C_IDENTITY` is set and differs from the identity
   linked into the command, the command exits with an error that names
   both. Run directly, without the driver, a command runs normally, so
   standalone use and development need no driver.
8. **Help.** `x2c help` lists external commands after the built-in ones,
   with summaries from the installed manifest (`<libexec>/commands.txt`).
   `x2c help <name>` and `x2c <name> --help` run `x2c-<name> --help`.
9. **Outside the bootstrap.** Commands are built by the stage compiler
   after `make build`. A command change never touches `bootstrap/` and
   never needs the self-host comparison.
10. **Gating.** `make commands-check` builds every command and runs each
    one's smoke tests in `commands/<name>/tests/`, and `agent-pr-check`
    runs it. Moving the REPL out of `src/` removes its code from the
    bootstrap refresh and the self-host comparison, which offsets part of
    that cost.

## Phases

Each phase is one delivery to `dev`. Phases 1 and 2 must land before the
REPL moves, because today's releases ship the REPL inside `x2c`.

1. **Mechanism, with `graph` as its first command.** Add `commands/`, the
   manifest, `make commands` with the `libx2c-dev.a` target,
   `make commands-check`, the libexec layout and `x2c env libexec`,
   dispatch, help, and the identity check. Move `tools/x2c-graph` to
   `commands/graph` as an experimental command; its private archive rule
   goes, and its `ast-parity` test becomes its smoke test. Add the
   category to the repo map in `AGENTS.md` and a "Commands" section to the
   CLI reference.
2. **Packaging.** `etc/x2c-payload.x` installs shipped commands into
   `<home>/libexec/x2c/` with `commands.txt`, and `make dist` carries
   them. The APE support payload carries `commands/`, and
   `x2c bootstrap` builds the shipped commands after the compiler, from
   the same objects. Release workflow changes follow
   `agents/releasing.md` and need Gary's release authorization.
3. **`repl`.** Move `src/repl.x`, `src/repl-session.x`, and
   `src/repl-input.x` to `commands/repl` as a shipped command, with its
   options moved from `src/cli.x`. The compiler services the REPL uses
   stay in the compiler: `Frontend.open_session`, REPL lowering in
   `src/comptime.x`, and the completion marker in `src/compiler.x`.
   `x2c repl` keeps working through dispatch, including
   `unittest/probes/run-native-modules.sh`. `tools/repl-spike` moves with
   it or is retired.
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

- Phase 1: `x2c graph` runs through dispatch in a checkout;
  `x2c help` lists it; a mismatched `X2C_IDENTITY` fails with both
  identities named; `make commands-check` runs in `agent-pr-check`.
- Phase 2: `make install PREFIX=...` and `make dist` produce
  `libexec/x2c/` with shipped commands only, and `x2c <name>` works from
  the installed prefix; an APE bootstrap produces the same directory.
- Phase 3: the REPL's existing probes and spike tests pass through
  `x2c repl`; `bootstrap/` no longer contains `repl*.c`.
- Phase 4: `x2c lint` runs through dispatch with the lint session's
  tests as its smoke tests.

## Plan review

- **Trusted facts.** The compiler identity, the home layout, and the
  compiler objects already exist and are produced by the current build.
  Commands reuse them; the only new check is the identity comparison,
  which protects against a command linked to a different compiler reading
  its data wrongly.
- **Reuse and new machinery.** The library archive already exists inside
  `tools/x2c-graph/Makefile`; phase 1 moves it to one shared target. New
  mechanisms are dispatch, the libexec directory, the manifest, and the
  maturity column. Each is needed because the driver must find, list, and
  ship programs it does not contain.
- **Idiom.** Commands are ordinary x2c programs built by the ordinary
  toolchain. Dispatch is an addition to the existing command table in
  `src/main.x`, not a plugin framework.
- **Diagnostics.** One new error: the identity mismatch. Unknown commands
  keep the current error. No other validators.
