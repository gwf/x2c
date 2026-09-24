# REPL command

`x2c repl` dispatches to the shipped `x2c-repl` executable. The
[REPL guide](../../docs/src/guide/repl.md) describes its input, commands,
supported language subset, and limitations.

`main.x` owns command options and compiler identity initialization.
`repl.x` owns the terminal loop and output. `repl-input.x` owns interactive
editing and history; `repl-session.x` owns submissions, completion, and
inspection over the compiler's session services. Those services stay in
`src/` because they use the parser, semantic transactions, and compile-time
lowering directly.

After building checkout commands, run `make commands-check` to exercise a
piped transcript and the direct session API. The transcript deliberately
includes a rejected declaration: it checks that later submissions still run
and that the process exits with status 1. The API test checks completion,
transaction rollback, retained results, and allocation-scope teardown.

The direct API test does not assert that live allocation counts return to an
empty frontend baseline. At migration, an exercised session retained nine
more allocations per round than an empty frontend session on macOS. The
[REPL guide](../../docs/src/guide/repl.md#failure-and-lifetime) describes
the session-lifetime limit.
