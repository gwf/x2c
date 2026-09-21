# x2c REPL research and checks

The experimental session now lives in `src/repl-session.x`, with the thin
terminal client in `src/repl.x`. The
[REPL chapter](../../docs/src/guide/repl.md) owns user-facing commands,
supported behavior, and limitations. This directory
keeps focused checks and research evidence from the spike, which started at
`f3aa43a5f1dcc3f9860496a9a7cf7080c6edec89` on `origin/dev`.

## Run and check

After the ordinary worktree setup and build:

```sh
builds/0/x2c repl
builds/0/x2c repl --dump --stats
tools/repl-spike/run < tools/repl-spike/demo.txt
python3 tools/repl-spike/check.py
python3 tools/repl-spike/retention.py 5000
```

`run` delegates to `builds/0/x2c repl`. The demo deliberately includes a
rejected declaration, so its piped session exits with status 1 after running
the remaining inputs.

`check.py` exercises the integrated terminal, direct session API, recovery,
inspection, and native comparisons. Set `X2C` to select a different compiler
for terminal checks. The direct API client is built against stage 0 compiler
objects, excluding `main.o`, under `unittest/build/repl-spike/`.
These focused scripts remain optional; they add no repository gate.

## Callable session API

Include `repl-session.x` from the compiler sources. Initialize the normal
frontend, preload its macro libraries, then call
`frontend.open_session(&unit)`. Close the `ParsedUnit` on either success or
failure. On success, `ReplSession.new(unit.compiler)` creates the submission
adapter; [api-check.x](api-check.x) is the complete executable caller.

`session.submit(source)` returns `ReplResult` with status `incomplete`,
`rejected`, `defined`, `executed`, `value`, or `failed`. It prints nothing and
retains no pending source prefix. Results carry source, diagnostics, an
optional message, typed syntax, lowered forms, and the result value or failure
cause. All borrowed storage remains valid until `unit.close()`.

`session.symbols()` returns a sorted List snapshot of published names and
kinds. `session.inspect(name)` returns `(value)`,
`(function (typed AST) (lowered FORMS))`, or NULL for an absent name. These
Lists borrow the same unit Context. Function inspection returns the canonical
Lists from successful submission, without parsing or lowering them again.
The existing name map owns inspection entries and redeclaration checks.

The session composes the ordinary frontend, parser, semantic transaction,
`Compiler.lower_comptime`, and Lisp evaluator. Stable binding IDs identify
session global cells. Publication waits for successful initialization;
effects on existing values survive failure. `Compiler.parse_submission`
owns the incremental input boundary and parser scratch restoration.

## Retention evidence and deferred work

[The retention experiment](retention.md) records the original eight-workload
comparison and the effect of reclaiming transaction scratch. The
[long-session assessment](long-session.md) records ownership fixes,
50,000-input mixed sessions, retained-result checks, and remaining questions.
Those reports are measurements of their recorded revisions, not guarantees
for every subsequent build. The scripts preserve repeatable probes and write
measurement logs under `debug/repl-retention/`.

Direct API checks compare teardown of used sessions against empty frontend
sessions; matching that baseline does not establish complete memory
stability. Canonical syntax, compiler caches, and evaluator allocations still
have session lifetime. Submission results must not outlive their unit.

AST transformation and installation, function replacement, rewind,
stop-and-copy, and a general collector remain separate design work. Edited
typed trees cannot blindly reuse binding IDs, and allocation scopes alone
cannot undo mutations to earlier values. Compile-time execution coverage is
developed separately; consume its ordinary lowering improvements rather
than creating another evaluator here.
