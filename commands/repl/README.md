# REPL command

`x2c repl` runs a native library playground. The
[REPL guide](../../docs/src/guide/repl.md) describes its commands, object
workflow, restart policy, and lifetime rules.

The [N-body demo](examples/README.md) loads an unchanged C program and walks
through function discovery, source inspection, and calls on its static data.
From the repository root:

```sh
./x2c repl < commands/repl/examples/nbody.repl
```

`main.x` reads REPL reporting options and delegates native build options to
the ordinary `CliRequest` parser. `repl.x` owns the terminal, command dispatch,
load/reset/replay state, and saved transcripts. `repl-input.x` owns editing,
completion display, and persistent text history.

`repl-worker.x` owns the native worker lifecycle and dedicated datum-framed
control pipes. Only requests, descriptions, diagnostics, completion data,
and formatted results cross those pipes. Worker standard output and errors
remain ordinary streams. An interactive worker receives standard input
through a private terminal while the supervisor relays input; piped source
uses native EOF. This keeps Ctrl-C under the supervisor's control without
passing native addresses between processes.

A candidate worker builds or restores a program, opens the compiler session,
and publishes its retained artifact description only when initialization
succeeds. The supervisor then retires the previous worker. Failed or canceled
candidate work preserves the current session. The supervisor creates each
fresh candidate's program directory and removes it when the candidate fails,
even when the candidate was killed. Reset and crash recovery restore
the last successful program description without replaying submitted code.
The tagged metadata snapshot stays beside the native module and frozen header.
The supervisor keeps its filename; a fresh worker reads it for reset or recovery.
Large header descriptions therefore stay inside the native worker.

The session service owns native compilation, typed objects, source snapshots,
and cleanup. Program loading and exploration use their corresponding command
modules. These services use the existing compiler frontend, native backend,
toolchain, and cache rather than an alternate interpreter or foreign object
protocol.

Run `sh commands/repl/tests/run.sh` after building the command. The complete
workflow must cover source loading, a header plus native archive, object
creation and calls, typed inspection, callbacks, failure recovery, and
snapshot/replay behavior. Focused terminal tests exercise process behavior
without requiring a desktop handoff.
