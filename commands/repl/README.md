# REPL command

`x2c repl` dispatches to the shipped `x2c-repl` executable. The
[REPL guide](../../docs/src/guide/repl.md) describes input, commands,
supported language subset, and limitations.

`main.x` owns options and compiler identity. `repl.x` owns terminal output;
`repl-input.x` owns editing and history. `repl-session.x` provides submissions,
completion, diagnostics, and inspection without terminal interaction.
`repl-load.x` builds an independent project meta helper for each loaded file,
publishes its public function and type declarations, and bridges calls
through the helper's existing data protocol. Each load retains its executable
across cache rebuilds. Source collection indexes refresh between loads;
previously published declarations keep their storage. A repeated load of
the same resolved path checks existing declarations before replacing its
helper. Call adapters borrow the file's persistent record, so saved functions
follow the replacement. `:info` uses compiler declaration formatting;
`:symbols` optionally filters names by prefix.
`repl-native.x` compiles prompt functions through session native staging.
Each function captures shared variable addresses and stable callable handles;
loaded calls therefore continue through the file's existing reload adapter.
`repl-native-types.x` reconstructs required loaded type declarations from
the compiler's canonical symbols. `repl-lower.x` lowers top-level typed
compiler ASTs to ordinary Lisp; `repl-runtime.x` and its Lisp source provide
interpreter storage and value operations.
These command services link against `libx2c-dev.a` for compiler parsing,
binding, typing, semantic transactions, and completion.

Each `ReplSession` owns its evaluator, lowering counters, and layout cache.
Call `session.close()` before closing its borrowed compiler unit and after
finishing all retained results. Native callable values can be borrowed from
the compiler's bindings; submission globals occupy session-owned native
storage shared by the evaluator and compiled prompt functions.
The session closes its loaded helpers before its compiler unit closes.
Native compiler meta execution and linked built-ins keep their existing
owners. Shared Lisp evaluation and compiled Match remain in
`lib/`; the Lisp wordcode engine and AUTO tier remain removed.

After building the command, run `sh commands/repl/tests/run.sh` for its
direct API and executable transcript checks. They exercise failure rollback,
retained results, completion, inspection, source loading and replacement,
and session teardown. The replacement tests also load and edit a temporary
copy of the autodiff module.
