# REPL command

> Status: active.
> The detailed plan for phase 3 of [external commands](external-commands.md),
> written 2026-09-24. It starts after that plan's phases 1 and 2 land.
> Nothing is implemented.

## Goal

Move the REPL out of the compiler into the shipped external command
`x2c-repl`, so `x2c repl` keeps working through dispatch. Then remove from
the compiler everything that existed only to run the REPL as a built-in
command. The compiler keeps the session services the REPL calls, because
they reach into the parser, tokenizer, semantic transactions, and
compile-time lowering.

## What the REPL is today

The REPL is three files, 2,670 lines in all:

| File | Lines | Depends on |
| --- | ---: | --- |
| `src/repl.x` | 440 | `cli.x`, `frontend.x` through the session, `lisp.x`, runtime stats |
| `src/repl-session.x` | 522 | `frontend.x`, `parse.x`, `comptime.x`, compiler state |
| `src/repl-input.x` | 1,708 | the runtime only: `common.x`, `file.x`, `scope.x`, `string.x`, termios |

`src/main.x` includes `repl.x` and calls `repl_run(request)` after
`Frontend.load_support`, which loads native modules. Only `main.x`
includes the REPL; nothing else in the compiler calls into it.

The compiler holds REPL-only code in two kinds.

**Command plumbing, which leaves the compiler:**

- `src/cli.x`:
  - the `repl_dump`, `repl_stats`, and `repl_verbose_stats` fields;
  - the `CLI_REPL` mask, the command row, and the `repl` bit in the `-h`
    and `--native-module` option masks;
  - the `--dump`, `--stats`, and `--verbose-stats` rows and their setters;
  - `_print_repl_help` and its help dispatch;
  - the `repl` entry in the top-level help text;
  - the "accepts no operands" case.
- `src/main.x`: `#include "repl.x"` and the `repl_run` dispatch.

**Session services, which stay as compiler API:**

- `src/frontend.x`: `Frontend.open_session` and the `session_source` path
  of `_start`.
- `src/parse.x`: `Compiler.parse_submission` and the `input_boundary` it
  sets.
- `src/compiler.x`:
  - the completion marker (`mark_completion`, `at_completion`,
    `__complete_here`, and the `<replcomp>` hook in `peek`);
  - `SymTxn.commit_transient`.
- `src/comptime.x`: `lower_repl`, `repl-init`, and the `session_globals`
  paths.
- The `__complete_here` calls in `expressions.x`, `statements.x`, and
  `parse.x` are no-ops unless a completion marker exists.

The runtime statistics the REPL prints stay in `lib/`, because unit suites
also use them: `Scope.stats`, `Pool.stats`, `MachineStats`, and the Lisp
call budget and auto-instrumentation.

Terminal handling is entirely inside `src/repl-input.x`: termios raw mode,
the `TIOCGWINSZ` window size, `TERM`, ANSI escapes, and in-memory history
with no history file. It moves with the file, leaving the compiler with no
termios or raw-mode code. The remaining terminal code in the compiler and
runtime serves builds and logging and stays: progress and receipts in
`src/report.x`, and colours in `lib/logger.x`.

## Design

1. **Sources.** Move `src/repl.x`, `src/repl-session.x`, and
   `src/repl-input.x` to `commands/repl/` unchanged except for their
   includes. Add `commands/repl/main.x` with `main`. The manifest row is
   `repl|shipped|Evaluate a supported x2c subset (experimental)`. The help
   text keeps "experimental" because the language subset is still limited;
   the command itself ships.
2. **Options.** The command parses its own options with `lib/args.x`:
   `--dump`, `--stats`, `--verbose-stats`, `--native-module <file>`
   (repeatable), and `-h`. The three REPL flags become fields of a
   `ReplOptions` struct in `commands/repl`, and `repl_run` takes it
   alongside the request.
3. **The request.** Add `CliRequest cli_request(Symbol command)` to
   `src/cli.x`. It returns the defaults `_parse_command` sets today,
   `_parse_command` uses it, and the REPL command calls it with `<repl>`,
   then adds its native modules. This is the one addition to the compiler.
4. **Startup.** `main` installs the embedded compiler identity (external
   commands, decision 7), initializes the environment, calls
   `Frontend.load_support`, and then calls `repl_run`, which is the same
   order `src/main.x` uses today.
5. **Native modules.** A module built by `x2c build --kind meta-module`
   carries x2c's identity. `x2c-repl` reports that identity and links the
   whole runtime as the compiler does, so the module's stamp check and its
   runtime calls work unchanged. On macOS the module was linked with
   `-bundle_loader` against `x2c`; it binds to the main executable's
   exported runtime symbols, which `x2c-repl` also exports. Validation
   checks this on macOS and Linux.
6. **Session services.** The services listed above stay where they are.
   Their doc comments say they serve session commands, so the generated
   compiler API pages group them under that heading. `repl-session.x`
   keeps saving and restoring the compiler's parser state directly; the
   `Compiler` struct is part of the headers commands include.
7. **Tests.** `commands/repl/tests/` holds:
   - `api-check.x`, moved from `tools/repl-spike`, which exercises
     `open_session`, `commit_transient`, and the statistics through the
     compiler library;
   - a transcript test that feeds a short session on standard input and
     compares the output, starting from `tools/repl-spike/demo.txt`.

   `unittest/probes/run-native-modules.sh` keeps running
   `x2c repl --native-module`, now through dispatch.
8. **`tools/repl-spike`.** It is retired. `run` is replaced by `x2c repl`,
   `api-check.x` and `demo.txt` move into the tests, and the Python harness,
   retention scripts, and notes are removed. Their findings are already
   recorded in the archived plans `repl-long-session.md`,
   `repl-retention-spike.md`, and `repl-session-spike.md`.

## Compiler cleanup

In the same change, because the built-in `repl` would otherwise shadow the
external one:

- Delete the command plumbing listed above from `src/cli.x` and
  `src/main.x`.
- The next bootstrap refresh drops `bootstrap/src/repl*.{c,h,o}`, since the
  stage build takes every `src/*.x`. This is an ordinary refresh with no
  change to emitted C.
- Update `unittest/compiler-fixtures/cli-help.help` and `cli-top.help`:
  `repl` moves from the built-in list to the external list.
- Regenerate the compiler API pages, the module catalog, and
  `docs/src/SUMMARY.md`. The `repl`, `repl-session`, and `repl-input`
  pages leave the compiler API, and the REPL's own internals are
  described in `commands/repl/README.md`.
- Update `docs/src/guide/repl.md` to say `x2c repl` is an external
  command. Remove the REPL modules from the compiler module lists in
  `docs/src/internals/architecture.md` and the repo map in `AGENTS.md`.

Compiler source shrinks by about 2,700 lines. Removing the session
services is out of scope, because the REPL needs them and they cannot live
outside the compiler's objects.

## Validation

- `x2c repl` runs through dispatch in a checkout and from an installed
  prefix. `x2c-repl` also runs directly.
- `commands/repl/tests` pass in `make commands-check`.
- `unittest/probes/run-native-modules.sh` passes, which covers a native
  module on the current platform. Run it on macOS and Linux before
  publication, because the module link differs.
- `git grep -n termios src` finds nothing.
- `bootstrap/src` has no `repl*` files after the refresh.
- `tools/gate-state.py ensure agent-pr-check`.

## Plan review

- **Trusted facts.** The inventory above was taken from current source.
  The frontend, parser, and lowering already enforce the session contract,
  and the command does not check it again.
- **Reuse and deletion.** The REPL's code moves without a rewrite. The
  compiler loses about 2,700 lines and its REPL command plumbing. The only
  addition is `cli_request`, which `_parse_command` also uses, so the
  compiler and the command share one set of request defaults instead of
  two.
- **Idiom.** The command is an ordinary x2c program that parses options
  with `lib/args.x` and calls the compiler through its existing API.
- **Diagnostics.** None are added. The identity check belongs to external
  commands.
