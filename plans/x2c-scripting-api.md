# Scripting API: commands, paths, arguments, and environment

> Status: done - 2026-09-16. Gary approved the API on 2026-09-16 after
> reviewing it as a book chapter. Supersedes the command and path surface
> recorded in `plans/x2c-scripting-library.md`.
> Notes: push 1 landed as `e718d95` and push 2 as `18637ee`. The literal
> fix grew to cover `==`, `<`, and `+` between aliases and `String` through
> their nearest shared ancestor, and Var reads into an alias through the
> ancestor's checked reader; that changed eight emitted Var reads in the
> compiler's own source, so push 1 needed the two-round bootstrap refresh.
> Nested-List pipelines stayed beside `Job.pipe`. `+` between an alias and a
> C string, `char *`, or `const char *` landed afterward. `%(` directly after
> a cast stays modulo; the tokenizer cannot tell a cast from a parenthesized
> operand, and the language reference gives the `(T) (%(...))` spelling.

## The result

A command stays a `List`, with `$` interpolation and `@` splicing unchanged.
`List.job()` is the one command entry point. It returns a `Job` that starts on
the first result requested and records that run, so a job runs exactly once
however many results are read from it. File operations move from `String` to
`class Path String;`. `String.env` becomes `Env.get`, and argument parsing
moves from `List` to `Args`.

The approved chapter text, which becomes `docs/src/guide/scripting.md`, is
`.context/scripting-api/commands-and-files-proposal.md` in the
`compiler-architecture-redesign-77de6e` worktree.

| Today | After |
| --- | --- |
| `cmd.run()`, `output()`, `lines()`, `status()`, `start()` | `cmd.job().run()`, `output()`, `lines()`, `status()`, `start()` |
| `cmd.options(map)`, `cmd.pipe(next)` | `cmd.job().options(map)`, `.pipe(next)` |
| `job.wait()` | `job.status()` |
| `List.arguments`, `List.parse_args`, `List.usage` | `Args.from_argv`, `Args.parse`, `Args.usage` |
| `%"NAME".env()` | `Env.get("NAME")` |
| file methods on `String` | the same methods on `Path` |
| `join_path`, `absolute_path`, `file_size` | `Path.join`, `Path.absolute`, `Path.size` |
| `String.temp_dir()` | `Path.temp_dir()` |

`String.sha256`, `File.sha256`, `Json.*`, `Var.json`, and `Var.pretty_json`
are unchanged.

## Decisions

Approved by Gary:

- A job captures standard output and passes standard error through, as the
  shell's `$(...)` does. `live()` inherits standard output instead.
- The entry point is `List.job()`, returning the existing `Job` class.
- File methods move to `class Path String;`.
- Pipes are `Job.pipe` now. A `|` operator comes later, defined as
  `Job.pipe`, and needs `|` added to the compiler's operator protocol table.
- `output` and `lines` raise `<cmd-fail>` when the status is not zero.
  `status` and `errors` never raise. The `<cmd-fail>` detail carries the
  captured `output` and `errors`.
- `live()` is its own method; `run()` is `live()` plus `check()`, and
  `check()` returns the job.
- `Path` renames `join_path`, `absolute_path`, and `file_size` to `join`,
  `absolute`, and `size`.
- The old `List` and `String` methods are removed outright.
- `Env.set` is left out until a script needs it.
- Changing options or adding a stage after a job starts raises `<bad-arg>`.

## Delivery

Two pushes, because a compiler capability must be in `bootstrap/` before any
`src/` or `lib/` code relies on it.

**Push 1, compiler capabilities.**

1. A C string literal converts to any type whose alias ancestry reaches
   `String`. Today `Path p = "build";` and `Path.exists("build")` pass a raw C
   string where an x2c `String` belongs, silently producing a wrong length
   and empty interpolation, for both `class Path String;` and
   `typedef String Path;`.
2. A percent literal is recognized where the tokenizer reads `%` as modulo
   after `)` or `}`: a `%(...)` command directly after a statement block,
   and `(Path) %"$a/$b"`.

**Push 2, the API.** `Job`, `Path`, `Env`, and `Args`; removal of the old
methods; every call site in `src/`, `lib/`, `tools/`, `etc/`, `examples/`, and
`unittest/`; the rewritten chapter; regenerated API pages.

## Lanes

- **T, tokenizer:** capability 2.
- **P, paths and arguments:** capability 1 as its own first commit, then
  `Path`, `Args` (including `Args.from_argv` for the script `main` the
  compiler synthesizes), and their call sites.
- **J, jobs and environment:** the `Job` redesign, `Env.get`, removal of the
  `List` and `String` process methods, and their call sites.

The coordinator integrates, writes the chapter from the approved text, and
migrates the held JSON batch's `tools/gen-package-index.x`.

Until push 1 is in `bootstrap/`, lanes P and J do not rely on either
capability in `src/` or `lib/`: they pass `%"..."` literals where a `Path` is
expected and avoid a `%` literal after `)` or `}`.

## Validation

Per lane: `make build`, focused unit suites and fixtures, then `make verify`.
Per push: `tools/gate-state.py ensure agent-pr-check` on the integrated tree,
staging after the gate. Converted tools must behave as before:
`tools/check-release.x` against the live site, and `etc/x2c-payload.x` by the
installed tree it produces. The chapter's samples must compile.

## Plan review

- **Facts already established.** `Job` already records its statuses and
  captured text, and `Job.wait` is idempotent, so the run-once model reuses
  that state instead of adding a cache. Typedef method lookup already tries
  the declared type before its parents, so `Path` methods do not collide with
  `String` methods. A `<cmd-fail>` raise transfers and never returns, so
  callers need no status check after `output`.
- **Reuse and deletion.** The five `List` wrappers around `_start` are
  deleted; `_start` becomes the launch behind `Job`. Every file method leaves
  `String`, and `List` keeps exactly one command method. No second launch
  path, cache, or registry is added.
- **Why idiomatic.** `Job` and `Path` are ordinary classes, so they get Var
  boxing, `repr`, equality, and cleanup from `class` rather than
  hand-written adapters. `Env` and `Args` are namespaces in the way `Json`
  already is.
- **Validators and fixtures.** Two compiler fixtures pin the capabilities;
  the literal one protects against wrong output that has no diagnostic
  today. The one new failure is `<bad-arg>` when options or stages change
  after a job starts, which protects against a job whose recorded run no
  longer matches its description. The `Job` unit tests pin run-once
  behavior. No other validator is proposed.
