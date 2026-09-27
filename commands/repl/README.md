# REPL command

`x2c repl` dispatches to the shipped `x2c-repl` executable. The
[REPL guide](../../docs/src/guide/repl.md) describes input, commands,
supported language subset, and limitations.

`main.x` owns options and compiler identity. `repl.x` owns terminal output;
`repl-input.x` owns editing and history. `repl-session.x` provides submissions,
completion, diagnostics, and inspection without terminal interaction.
`repl-lower.x` lowers typed compiler ASTs to ordinary Lisp; `repl-runtime.x`
and its Lisp source provide interpreter storage and value operations.
These command services link against `libx2c-dev.a` for compiler parsing,
binding, typing, semantic transactions, and completion.

Each `ReplSession` owns its evaluator, lowering counters, and layout cache.
Call `session.close()` before closing its borrowed compiler unit and after
finishing all retained results. Native callable values can be borrowed from
the compiler's bindings; submission globals belong only to the interpreter.
Native compiler meta execution, linked built-ins, and helper execution keep
their existing owners. Shared Lisp evaluation and compiled Match remain in
`lib/`; the Lisp wordcode engine and AUTO tier remain removed.

After building the command, run `sh commands/repl/tests/run.sh` for its
direct API and executable transcript checks. They exercise failure rollback,
retained results, completion, inspection, and session teardown.
