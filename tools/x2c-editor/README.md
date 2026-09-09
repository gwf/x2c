# Semantic editor worker

The compiler owns semantic requests through private `x2c editor` dispatch.
See the book's
[VS Code setup and configuration](../../docs/src/reference/cli.md#vs-code-diagnostics-definitions-and-hover).

For users with an explicit legacy `x2c.semantic.workerPath`, this directory
retains a thin compatibility launcher:

```sh
make -C tools/x2c-editor
make -C tools/x2c-editor test
```

The launcher executes the configured compiler's `editor` command and has no
separate compiler archive or adapter build. These commands consume `builds/0`;
they do not rebuild the shared compiler or change publication gates. `test`
checks both direct compiler and compatibility transports. The extension tests
run with `npm ci && npm test` in `etc/vsc-extension`.

## One request

The extension starts a fresh process for each analysis. Its private arguments
are the response filename, logical source filename, query kind, byte offset,
overlay count, then triples of logical path, snapshot filename, and dirty flag.
After `--`, the existing compiler CLI parses ordinary command arguments.
Empty arguments select a discovered project or the current source file.

Snapshots live in a request-owned temporary directory. The worker preserves
logical paths and reads through `SourceView`, including empty and new files.
The request owns configured overlays; `ParsedUnit` owns disk text, semantic
facts, and diagnostics. Compiler children borrow those unit-owned stores.
The response is serialized before the unit closes, then the process exits.

Only the dedicated response file contains JSON. Macro stdout and stderr are
captured separately. The response contains diagnostics, an optional definition
or hover, and exact source text needed for their byte ranges. VS Code positions
are derived from those snapshots using UTF-16 offsets. No source text corpus
or semantic index is retained across requests.

Changed document revisions cancel older work. On POSIX systems cancellation
terminates the worker's process group, including native preprocessor children,
before deleting snapshots. Windows cancellation terminates the worker itself;
the current compiler/worker build is intended for supported Unix hosts.

## Boundaries

The ordinary manifest parser owns target, profile, include, and package
configuration. Ambiguous or missing target ownership is a configuration error.
An included document outside selected target inputs needs its owning source
or an explicit translation configuration; analysis of that source still uses
its included unsaved overlays.

Semantic requests collect source declarations without replaying header-symbol
artifacts, which do not retain declaration locations. Binding locations pass
through actual symbol contributions and scope identities. They are not
reconstructed by matching source spellings or by parsing another AST.
Definitions and types are unavailable when the compiler has not collected the
declaration, such as a local `Unit` macro expansion in an included file.

Native CPP modes read disk through the selected native toolchain. A changed
primary is rejected before preprocessing; actual dependency/source reads are
checked before returning results so a consumed dirty include cannot silently
produce stale semantics. Configuration and native errors stay in the worker
and do not terminate the extension. Arbitrary file I/O in user macros retains
ordinary filesystem behavior.

The extension activates semantic execution only in trusted local workspaces.
Completion, rename, workspace indexing, incremental caches, and general LSP
transport are outside this initial implementation.
