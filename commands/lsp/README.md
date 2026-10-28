# Language server

`x2c lsp` serves one workspace over stdio using LSP 3.17 and JSON-RPC 2.0.
Build the experimental command with `make commands`. The driver enables
allocation accounting before starting the server. A direct `x2c-lsp` invocation
requires `X2C_SCOPE_ACCOUNTING=1` for its retained-memory restart policy.
Start the compiler from its workspace directory. The driver selects its
matching `x2c-lsp` executable.

Send ordinary compiler arguments in `initializationOptions.arguments`, for
example `["build", "--target", "app"]`. An empty list selects the discovered
project or the current source. Only `build` and `translate` configurations are
supported. The server reports compiler frontend diagnostics, definitions, and
hover. It accepts full-document changes and keeps unsaved source overlays.
Native CPP symbol modes cannot analyze unsaved source text.

Unsupported analysis commands, unsaved CPP input, and documents without a
unique selected target produce a `window/showMessage` notice. Invalid CLI
options and malformed or invalid project configurations retain the CLI's
existing behavior: they print an error and terminate the server. Correct the
configuration and restart the client in those cases.

The server converts UTF-16 LSP positions to compiler byte offsets. One resident
frontend keeps at most one source unit open. Whole-unit dependency invalidation
uses each analyzed document's read set. Diagnostics wait until queued changes
have drained. Queued requests can be cancelled; an analysis already running
finishes before the next message is handled.

At idle checkpoints, 64 MiB of retained allocation growth causes the server
to replace itself while preserving its PID, stdio connection, current buffers,
and exported results. The next analysis rebuilds compiler state. Macro and
native-module process state resets. The budget limits retained history between
checkpoints; one analysis or input burst can exceed it.

Protocol messages use `Content-Length` framing. Compiler output goes to stderr.
`shutdown` returns a null result; `exit` terminates the process. EOF also exits.
The command does not index the workspace in the background or run a C compiler.

Run `commands/lsp/tests/run.sh` after building the command for the framed
protocol smoke test. `make commands-check` includes that test.

For an optional, longer checkpoint probe, run
`python3 commands/lsp/tests/restart.py "$PWD"` from the checkout root. It
uses the production budget and writes an evidence report in its temporary
directory. It is separate from `make commands-check`.
