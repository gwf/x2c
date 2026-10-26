# Logger and Diagnostics Guide

This is the canonical guide to the two related but distinct reporting
modules. `lib/logger.x` owns general structured event delivery.
`src/diagnostics.x` owns bounded compiler-error storage and prints each
entry through one compiler.

## Local report catalogues

Named diagnostics keep wording and construction with the code that owns the
condition. A catalogue used by one file stays near its top as static macros.
Several call sites may share one definition. Actual shared consumers include
an owner's `*-reports.x` directly; those definitions remain nonstatic.
A large local catalogue may use a sibling file, but separation is optional.
Do not share unrelated conditions merely because their wording matches.

Compiler catalogue macros use one dot: `$action.owner_condition`. The owner
names the responsibility, not the diagnostic category. `$fail` reports and
transfers or terminates; `$report` records or emits an error and returns;
`$warn` records or emits a warning. `$note` constructs note text or a notes
List, and `$reason` constructs a reason String. `$progress` and `$debug`
distinguish ordinary status and debug output in mixed catalogues. Existing
structured Error raises retain `$error` and their runtime conventions.

Arguments are context, explicit source site when applicable, then semantic
operands. A site may be a Token, recorded location, or analysis origin, as
required by the existing reporter. Preserve NULL fallback versus an explicit
current token. The caller selects the condition; the definition owns its
message, category, and notes. Use an expression body for one reporting call
and a scoped block for temporary construction.

Keep typed helpers when they calculate context or notes. Do not add forwarding
macros around them. Generic renderers, pass-through reporters, native failure
floors, and short structured raises keep their existing representation.
Reporting owners retain guards, severity, recovery, cleanup, and deferred
collection. A returning stderr error must not acquire terminating behavior.

Component diagnostic macros also used by generated `linked-meta.x` remain
nonstatic in their owning component files. The linked-meta generator's
operation discovery does not expand macros; a direct report needed to identify
a compiler-dependent meta body remains direct rather than changing discovery.

These are ordinary compile-time expansions, not runtime message registries or
catalogue installers. Runtime, package, and command catalogues keep their
existing action prefixes, including `$refusal` and `$decline` for REPL actions.

## Logger contract

A `Logger` is an opaque event service. It serializes its level filter, event
clocks and sequence, sink registration order, built-in sink contexts, and
rendering scratch space. A `LogSink` is an opaque handle valid until Logger
destruction. Removal retires the handle, releases any owned sink context
exactly once, and makes later removal attempts return false.
`Logger.min_level` and `Logger.sink_count` are the inspection boundaries;
callers do not inspect either handle's representation.

`Logger.add_sink`, `Logger.remove_sink`, `Logger.clear_sinks`, and
`Logger.free` raise `<bad-state>` when called from inside a sink emitter,
because emission is walking the list they would change. An emitter may log
again; it may not reshape the Logger it is running under.

`Logger.new(min_level)` accepts `<trace>`, `<debug>`, `<info>`, `<warn>`,
`<error>`, `<fatal>`, or `<off>`. It installs no sinks. `<off>` is a minimum
level, never an event level. Unknown levels are
invalid: `Logger.level_priority` returns `-1`, `Logger.set_min_level` leaves
configuration unchanged and returns false, and event delivery ignores them.
`Logger.initialize` separately creates the module-owned default Logger and
adds its stderr sink.

`Logger.should_log` and `log_should_log` are the construction guard for
expensive fields. They return true only when the event level is valid and at
or above the threshold and at least one sink is active. Callers must guard
before building dynamic Lists or Strings. In pseudo-code:

```x2c
if (log_should_log(<debug>, <parser>))
  log_debug(<parser>, %(node $(expensive_node.repr())));
```

A category names an event; it never suppresses one. Level is the only
filter, and a sink that wants a subset reads `event->category` itself.

Event fields are Lists of two-element `(key value)` Lists. Percent-literal
interpolation owns boxing: use `$name` or `$(expression)` for computed values.
An unquoted name without interpolation is a literal Symbol, not the value of
the variable with that name.

An accepted event becomes one immutable `LogEvent` containing its numeric
sequence, wall-clock microseconds, monotonic elapsed microseconds, level,
category, and original fields. The first accepted event establishes sequence
zero and the Logger's monotonic origin. Every sink receives a borrowed
`const LogEvent *` with identical metadata; the pointer is valid only during
the callback.

`Logger.add_sink` appends a custom emitter, optional flusher, and borrowed
`Var data`, returning its removal handle. Logger never frees arbitrary sink
data. `remove_sink` is constant time and idempotent; `clear_sinks` removes
every sink.
`add_stderr_sink`, `add_file_sink`, and `add_memory_sink` install owned
built-in contexts. Files are borrowed and never closed. Sinks added, removed,
or cleared by an emitter are committed after the outermost emission, so an
event and recursive events observe one stable registration-order snapshot.
Freeing the Logger from an emitter is unsupported. Logger is reentrant, and
calls from different threads are serialized.

Text sinks render
`M:SS.mmm level/category key=repr` directly through reusable Buffers. A
Logger's first text event includes `start_time`; stderr selects ANSI color for
a TTY and flushes after every event, while file sinks remain buffered.
`Logger.flush`, Logger destruction, shutdown, and `<fatal>` flush all active
sinks. File removal/destruction flushes but does not close the borrowed File.
`Var.write_repr(value, buffer)` is the rendering boundary. Built-in scalar,
pointer, String, Symbol, List, Array, and Map writers match `Var.repr`
byte-for-byte without a canonical intermediate String. A custom descriptor
may install `VarMethods.write_repr`; descriptors without one fall back to
their existing `repr` callback.

Memory sinks prepend newest-first entries shaped as
`(sequence wall_time_us elapsed_us level category fields)`. The first three
values are numeric Vars. A fields List already safe in the Logger's
creation-time pools keeps its identity; a worker-private fields List and its
immutable String, Atom, and List children are copied into those pools.
Captured entries therefore survive the emitting Context.

`log_set_global_logger` installs a borrowed Logger and returns the previous
borrowed value, which makes scoped replacement/restoration explicit. The
global `log_*` helpers use the active Logger. `Logger.shutdown` clears global
state, flushes a caller-owned active Logger, and frees only the module-owned
default Logger.

`Logger.initialize` initializes Error after installing the default stderr
Logger, then registers `Logger.error_handler` as an observing handler. It
renders only the newest `<abort>` or `<log>` Error as an `<error-report>`
event. `<collect>` remains quiet for its boundary reporter and `<ignore>`
remains quiet permanently. The handler always declines, so Error still owns
consumption, transfer, and the fatal floor.

The Logger suite owns level filtering, sink fan-out, field formatting,
memory capture, recursion during emission, allocation stability, Error
rendering, flushing, and global-helper behavior. Async queues, rotation,
JSON serialization, and ownership of caller Files/data are outside this
contract.

## Diagnostics contract

`Diagnostics.new(printer, limit)` creates a store; a NULL printer collects
without streaming. It stores entries in chronological order in an Array;
`Diagnostics.entries` returns a List snapshot in that order. Each entry has
these
associative-list fields:

| Field | Value |
| --- | --- |
| `code` | Symbol identifying the compiler boundary |
| `severity` | Symbol the submitting operation chose: `error`, `warning`, or `note` |
| `message` | String presented to the user |
| `location` | location List, or typed nil/List when absent |
| `notes` | List of note Strings, or typed nil/List when absent |

The severity belongs to the submitting operation, not to the code, so a
category such as `literal`, `region`, or `macro` carries both errors and
warnings and each entry states its own.

When present, a compiler location has exactly these fields:

| Field | Meaning |
| --- | --- |
| `file` | source filename |
| `line` | one-based source line |
| `column` | one-based byte column |
| `length` | offending token width in bytes |
| `position` | absolute zero-based byte offset in the source |

The user renderer consumes `length` directly. It clamps a highlight to the
current source line and prints at least one caret. Tabs before the offending
token are preserved so the caret remains aligned with the displayed source.
There is no alternate `span` location contract.

The generic Diagnostics store retains its configurable limit. Zero disables
the limit. Reaching a limit greater than one appends one `<limit>` entry with
the message `too many errors, stopping`; later reports are ignored. A report
equal to a stored entry is ignored, because some producers derive the same
failure twice.

`Compiler.new` starts with a limit of one, and child compilers inherit their
owner's limit. The frontend applies
[`--max-errors`](../docs/src/reference/cli.md#compiler-diagnostics).
`--diagnostics-file` makes `Compiler.print_diagnostic` append one JSON line
per entry to a descriptor opened once in `main`; forked translation workers
inherit it.

## Compiler flow

`Compiler.report_error` constructs the location from the current or supplied
Token and passes the entry to Diagnostics, whose printer is the compiler
itself. Compilers that share one store take the stream in turn with
`Compiler.own_diagnostics`. A speculative parse brackets its reports with
`Diagnostics.hold` and `Diagnostics.release`, which either discards them or
keeps and prints them. During `Compiler.full_parse`, the reporter raises
`<malformed>` with the diagnostic category. A filtered catch rewinds to the
start of the failed top-level declaration and skips it whole. State set before
a raise must be restored by `defer` or `with`, or later declarations parse in
the wrong mode. A `<malformed>` transfer out of a macro expansion continues
outward, since its diagnostic is already reported. Outside that recovery region
the reporter exits with status 1.

Tokenizer helpers must honor their scanner preconditions. In particular, the
tokenizer calls `scan_identifier` only after checking for an identifier-start
character. This lets malformed literal references reach `src/literals/literals.x`,
which owns the structured parse error and syntax hint.

## Executable proof

- `unittest/test-logger.x` verifies Logger behavior.
- `unittest/test-diagnostics.x` verifies entry ordering, limits, reset,
  printing, and held reports.
- `unittest/compiler-fixtures/parse-error.x` verifies the ordinary parse
  failure boundary.
- `unittest/compiler-fixtures/diagnostic-width.x` fixes filename, one-based
  line and column, token-width carets, notes, limit notice, and exit status.
- The `parenthesized-{list-unquote,string-unquote,list-splice}` fixtures prove
  unsupported `$()` and `@()` literal forms exit 1 with positioned parse
  diagnostics, without an assertion or signal. The braced malformed fixtures
  cover empty, missing, and mismatched delimiters.
