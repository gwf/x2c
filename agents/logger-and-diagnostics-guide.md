# Logger and Diagnostics Guide

This is the canonical guide to the two related but distinct reporting
modules. `lib/logger.x` owns general structured event delivery.
`src/diagnostics.x` owns bounded compiler-error storage and forwards each
entry to one emitter callback.

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
  log_debug(<parser>, %((node ${expensive_node.repr()})));
```

A category names an event; it never suppresses one. Level is the only
filter, and a sink that wants a subset reads `event->category` itself.

Event fields are Lists of two-element `(key value)` Lists. Percent-literal
interpolation owns boxing: use `$name` or `${expression}` for computed values.
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
event. `<ignore>` remains quiet for its boundary reporter and `<ignore>`
remains quiet permanently. The handler always declines, so Error still owns
consumption, transfer, and the fatal floor.

The Logger suite owns level filtering, sink fan-out, field formatting,
memory capture, recursion during emission, allocation stability, Error
rendering, flushing, and global-helper behavior. Async queues, rotation,
JSON serialization, and ownership of caller Files/data are outside this
contract.

## Diagnostics contract

`Diagnostics.new(emit, owner, limit)` creates a store. It records entries
newest-first internally and `Diagnostics.entries` returns them in report
order. Each entry has these associative-list fields:

| Field | Value |
| --- | --- |
| `code` | Symbol identifying the compiler boundary |
| `message` | String presented to the user |
| `location` | location List, or typed nil/List when absent |
| `notes` | List of note Strings, or typed nil/List when absent |

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
the limit. Reaching a positive limit appends one `<limit>` entry with the
message `too many errors, stopping`; later reports are ignored.

The compiler chooses a limit of one in `Compiler.new`. Consequently the CLI
prints one ordinary diagnostic followed by the existing limit notice. This is
a compiler policy, not a restriction on the reusable Diagnostics API.

## Compiler flow

`Compiler.report_error` constructs the location from the current or supplied
Token and passes the entry to Diagnostics, whose emitter is the compiler's own
`print_diagnostic`. Compilers that share one store take the stream in turn
with `Compiler.own_diagnostics`. During `Compiler.full_parse`, the
reporter raises `<malformed>` with the diagnostic category. A filtered catch
synchronizes at the next top-level boundary. Outside that recovery region the
reporter exits with status 1.

Tokenizer helpers must honor their scanner preconditions. In particular, the
tokenizer calls `scan_identifier` only after checking for an identifier-start
character. This lets malformed literal references reach `src/literals.x`,
which owns the structured parse error and syntax hint.

## Executable proof

- `unittest/test-logger.x` verifies Logger behavior.
- `unittest/test-diagnostics.x` verifies entry ordering, limits, reset, and
  emitter forwarding.
- `unittest/compiler-fixtures/parse-error.x` verifies the ordinary parse
  failure boundary.
- `unittest/compiler-fixtures/diagnostic-width.x` fixes filename, one-based
  line and column, token-width carets, notes, limit notice, and exit status.
- The `parenthesized-{list-unquote,string-unquote,list-splice}` fixtures prove
  unsupported `$()` and `@()` literal forms exit 1 with positioned parse
  diagnostics, without an assertion or signal. The braced malformed fixtures
  cover empty, missing, and mismatched delimiters.

Ordinary checks never rewrite these expected artifacts. Use
`make verify-fixtures-update` only when deliberately accepting reviewed
compiler output changes.
