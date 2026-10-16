# Semantic editor command

The shipped `x2c-editor` command serves one private request per process.
`x2c editor` executes the matching command from the compiler installation.
Build it with `make commands`; normal installations include it.

The adapter owns argument decoding, overlays, project target selection, and
JSON responses. It uses the shared compiler frontend for semantic analysis.
The driver replaces its process, preserving editor process-group cancellation.

See the [transport and compatibility launcher](../../tools/x2c-editor/README.md)
for request arguments, response lifetimes, and optional semantic tests.
`x2c help editor` prints the private invocation shape. The protocol is not a
public compiler API.
