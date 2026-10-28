> Status: active - phase 1 ready for shared integration; phases 2-4 pending
> Drafted 2026-10-28 against `gwf/repo-survey-major-features-933090`
> (`f5d0eb2fb`). Gary authorized execution on 2026-10-28 with subagents.
> Ready PRs go to the shared integration agent, which owns full gates.
> Phase 1 lands before phases 2 and 3 start. Phase 4 waits for the extension
> release that uses the language client.

# Resident language server: `x2c lsp`

## Result

Add an external command `commands/lsp` that the driver runs as `x2c lsp`.
One process serves one workspace over stdio using the Language Server
Protocol (LSP 3.17, JSON-RPC 2.0, `Content-Length` framing). Any editor with
an LSP client gets diagnostics, definition, hover, completion, symbols,
references, rename, and semantic tokens from the same compiler the user
builds with. The VS Code extension in `etc/vsc-extension` becomes an LSP
client, and the one-request `x2c editor` command is retired after the
extension switches.

The server links the compiler in-process, as `commands/editor` does, and
keeps one configured `Frontend` plus request-owned analysis results between
messages. The compiler analyzes whole units; that is the only invalidation
granularity the server offers.

## Feasibility probe (2026-10-28)

- `Makefile` target `command-artifacts` builds every manifest command from
  `commands/<name>/*.x`, `builds/0/commands/identity.x`, and
  `builds/0/libx2c-dev.a`. `commands/editor/editor.x` includes
  `frontend.x`, `sourceview.x`, `project/project.x`, and `emit/emit.x` and
  calls `Frontend.new`, `frontend.open`, and `unit.compiler` directly. The
  compiler is already linked in-process; no subprocess is needed.
- `builds/0/x2c --help` lists `editor`, `graph`, `lint`, `package`, and
  `repl` as external commands. `builds/0/libexec/` holds `x2c-editor`.
- `x2c editor RESPONSE SOURCE hover 23 0 -- translate SOURCE` on a two-line
  file returned `{"diagnostics":[],"file":...,"hover":{"start":23,"end":28,
  "text":"int value(void);\n"},"sources":[{"file":...,"text":...}]}`.
  A `definition` query with one unsaved snapshot (`COUNT 1`, dirty flag
  `1`) answered from the snapshot text, not the disk file. A parse error
  returned `{"code":"parse","severity":"error","start":26,"end":27,
  "message":"expected atomic expression",...}`. Offsets are UTF-8 bytes.
- An undeclared identifier produced no diagnostic: the frontend leaves C
  name resolution to the C compiler. The server reports frontend
  diagnostics only, as `x2c editor` does today.
- Completion is a compiler mechanism, not a REPL one:
  `Compiler.mark_completion` and `_x2c_complete_here` in
  `src/compiler/parsing/tokens.x` retag the token at a byte position and
  raise `<replcomp>` with the grammar role, visible symbols, and keywords
  from the parser sites in `src/statements.x`, `src/expressions/syntax.x`,
  `src/parse/declarators.x`, and `src/parse/types.x`.
  `ReplSession.complete` in `commands/repl/repl-session.x` wraps that
  mechanism in session state (`session.names`, `evaluator`, `accessors`,
  `internal`) and a private `_completion_filter`; that wrapper is not
  shareable, the compiler mechanism is.
- `Compiler.definition_rows(ast)` in `src/generate/definitions.x` returns
  the rows `--dump-definitions` prints; the server calls it in-process
  instead of parsing dump text.
- `commands/graph/snapshot-query.x` (`_sq_serve_request`) is a working
  resident JSON-over-stdio loop: `Stdin.readline`, `Json.parse`, one
  isolated `Context` per request, `Var.json` reply. `lib/file.x` has
  `File.readblock(size)` for a fixed-length body.

## Architecture

- Process model: the editor starts `x2c lsp` with the workspace root as its
  working directory. One process serves one workspace. No daemon, socket, or
  shared cache between processes. Exit on `exit`; EOF also exits.
- Compiler access: in-process through `Frontend`, `SourceView`, and
  `ProjectBuild`, exactly the owners `commands/editor/editor.x` uses.
- Configuration: `initializationOptions.arguments` (the current
  `x2c.semantic.arguments` list) becomes the `CliRequest` after `--`, with
  the same `build` default and `build`/`translate` restriction as
  `editor.x`. One current `Frontend` serves the selected target. A target
  change closes the previous unit before configuring the next frontend.
  `source_facts` is on.
- Target selection: move `editor.x`'s `_project_target` into
  `src/project/` as `ProjectBuild.owning_target(CliRequest, String source)`,
  returning the selected request or NULL with the existing ambiguity
  failure. Both commands call it until `editor` is retired.
- State kept across requests, all owned by the server:
  - `SourceView` overlays for open documents (see Unsaved buffers).
  - One open `ParsedUnit`, the unit of the document most recently analyzed.
    `Frontend` units nest and close in reverse order, so the server never
    holds two. A request on another document closes the current unit and
    opens that document's unit; this costs what one `x2c editor` process
    costs today, without the process start.
  - Per document, an exported `Analysis` record in a server `Context`:
    diagnostics as LSP `Diagnostic` Maps, definition rows copied from
    `definition_rows` (name, display, kind, range), and the set of files the
    unit read (`c.deps.keys()` and `c.source_texts.keys()`, as
    `_changed_dependency` enumerates today). Exported values are Strings and
    ints, so they survive `unit.close()`.
  - Hover, definition, completion, and references read `source_occurrences`,
    `source_definitions`, and `Type` values, which borrow the unit
    `Context`. They are served from the open unit, reopening it if needed.
- Invalidation: a `didChange`, `didSave`, `didClose`, or watched-file
  notification for file F discards the `Analysis` of every document whose
  read set contains F, and closes the open unit if its read set contains F.
  The next request or publish reanalyzes. Nothing finer exists: the
  compiler has no incremental parse.
  Overlay mutations also close the open unit before `SourceView.set` or
  `unset`, even when its read set is unrelated. `SourceView` requires
  configuration before a frontend unit opens. This preserves cached exported
  results but can require a later hover to reparse after an unrelated edit.
- Diagnostics publishing: after each `didOpen`, `didChange`, and `didSave`
  the server reanalyzes that document and sends `publishDiagnostics`, but
  only when no further message is already waiting on stdin (`poll` with
  zero timeout). Typing bursts therefore coalesce without a timer thread.
- Cancellation: the server is single-threaded and answers in order. Before
  starting a request it drains waiting messages; a `$/cancelRequest` for a
  queued id answers error `-32800` without analysis. A request already
  being analyzed completes; one unit analysis is the bound, as today.

## LSP features and their compiler facilities

| Feature | Facility | Phase |
| --- | --- | --- |
| `publishDiagnostics` | `c.diagnostics()` rows converted as `editor.x` `_diagnostic` does | 1 |
| `textDocument/definition` | `_occurrence` over `c.source_occurrences`, `c.source_definitions[binding]` | 1 |
| `textDocument/hover` | occurrence `Type.declaration_ast`, `c.code_pretty_string(c.emit(...))` | 1 |
| `textDocument/completion` | overlay with marker text at the cursor, `mark_completion`, catch `<replcomp>`, filter rows and keywords by prefix and role | 2 |
| `textDocument/documentSymbol` | `Compiler.definition_rows(unit.ast)` | 2 |
| `workspace/symbol` | the cached `Analysis` rows of analyzed documents, filtered by substring | 2 |
| `textDocument/references` | `source_occurrences` of every target input unit whose definition location equals the selected binding's definition location | 3 |
| `textDocument/rename` | references, as one `WorkspaceEdit`; refused when the definition lies outside the workspace or has no source range | 3 |
| `textDocument/semanticTokens/full` | `Tokenizer.scan` on the document text; token `type` mapped to LSP token types | 3 |

Completion details: the server copies the document text with
`__x2c_completion__` inserted at the cursor into a private overlay, runs
`frontend.start`, `unit.compiler.mark_completion(offset)`, then `collect`
and `parse` inside `try`, and catches `<replcomp>`. Candidate rows are
`(spelling Type)` from `c.sym.visible_symbols()`; the server keeps the
role rules the REPL applies (`type` role offers typedefs and type macros,
`expr` and `statement` roles exclude them, `members` rows are names) in a
filter of about 30 lines, without the REPL's session and internal-name
rules. Completion of a `meta` declaration form returns no candidates, as
the REPL decides.

References and rename analyze each selected target input sequentially
through the same one-unit rule, matching bindings by definition location
(file, start, end) because binding numbers are per unit. A workspace
without a manifest searches only the current document. The graph snapshot
is not used: it indexes saved files, not overlays, and loads in seconds.

Out of scope for every phase here: formatting (lint's formatter is
whitespace-only and lives in `commands/lint/formatting.x` inside the lint
command; linking it into another command is a later decision), code
actions, signature help, inlay hints, folding, call hierarchy, semantic
token deltas or ranges, background workspace indexing, diagnostics from the
C compiler, native CPP symbol modes with unsaved text (refused with the
existing message), multi-root workspaces, and any transport other than
stdio.

## Transport and JSON

- Framing: read header lines with `Stdin.readline` until the empty line,
  parse `Content-Length`, read the body with `Stdin.readblock`. Write
  `Content-Length: N\r\n\r\n` plus `Var.json(message)` to `Stdout`, then
  flush. Everything else the compiler prints goes to stderr; macro output
  on stdout would corrupt the stream, so the server redirects fd 1 to
  stderr for the analysis and keeps its own `File` on the original fd 1.
- JSON: `Json.parse` for input, `Var.json` for output, `Json.bool` for
  `true`/`false`. Message Maps are built with Map literals. Frame and JSON
  parsing use an isolated `Context`; queued values move to server storage.
  Handlers run under the retained unit or server lifetime so they can close
  the open unit. Idle checkpoints reclaim accumulated process history.
- Positions: LSP uses UTF-16 line/character; the compiler uses UTF-8 byte
  offsets. The server converts both ways against the overlay text it owns
  (the `positionAt` and `byteOffset` rules in `semantic.js` move into the
  server). `positionEncoding` negotiation is not offered; one conversion
  path serves every client.
- Errors: a malformed frame or JSON body answers `-32700`; an unknown
  method answers `-32601` for requests and is ignored for notifications; a
  configuration failure (`_fail` cases in `editor.x`) becomes
  `window/showMessage` once per distinct text and empty results.

## Unsaved buffers

`didOpen` and `didChange` (full sync, `TextDocumentSyncKind.Full`) call
`SourceView.set(path, text, dirty)`; `didSave` sets `dirty` to 0 with the
saved text; `didClose` removes the overlay so the disk file is read again.
`SourceView` has no removal today; add `SourceView.unset(path)`, three
lines, next to `set`. The same `SourceView` instance stays attached to the
`Frontend`'s request for the process lifetime. `file://` URIs are decoded
to absolute paths and `Path.absolute` keeps logical identity, as in
`_snapshots`. Non-`file` URIs are ignored.

## Delivery

### Approved lifetime revision (2026-10-28)

The first implementation exposed a lifetime gap in the original architecture.
The server Context retains every exported snapshot String. A paced probe with
100 distinct 128 KiB edits grew RSS from 181,728 KiB to 192,752 KiB.
Compiler collection also retains historical declaration rows deliberately:
`Compiler.refresh_source_collections()` drops indexes, not their backing values
(`src/collect/cache.x`). Collection promotes retained Strings and Lists to the
root pool. Native modules and the source-path cache also have process lifetimes.

Gary requested a revised lifetime design before submission. Two smaller
alternatives do not reclaim the full history:

- Keeping document bytes in Buffers and canonicalizing only the current
  snapshot would bound overlay Strings, but not compiler-global history.
- Rebuilding the isolated server Context would reclaim its own history, but
  not values promoted to the root pool or compiler process scopes.

Proposed replacement boundary: restart the language server in place with
`exec` at an idle checkpoint when retained allocation growth exceeds a fixed
budget. Keep the same PID and stdio connection. No supervisor or second
analysis process is introduced. Serialize initialization arguments, current
open overlays and dirty flags, exported Analysis records, document versions,
and notice deduplication
state into an anonymous inherited temporary-file descriptor. Checkpoint only
after queued messages and pending diagnostics drain, so no in-flight request
is replayed. Stop the compiler's meta helper and release its temporary state
through its existing owner before exec. Restore protocol stdout before the
new executable starts. Resume without sending a second initialize response.
Restore exported Analysis records; never serialize borrowed compiler values.

Use the existing allocator counters to compare retained growth with the first
completed analysis of the generation; a proposed initial budget is 64 MiB.
This bounds history between checkpoints, not the size of one document,
analysis, or queued input burst. A fresh generation establishes its baseline
after restoring live documents and completing its first analysis.
Before that first analysis, use a cold baseline so edits to unrelated buffers
can still trigger checkpoints. Replace that baseline once after compiler
setup, avoiding repeated restarts caused only by cold setup allocations.

The change stays in `commands/lsp/`; it does not change compiler/runtime
ownership or ABI. Its costs are serialization proportional to current live
buffer bytes, temporary storage of those bytes, and cold compiler/meta setup
after each checkpoint. Native-module and macro process state resets at that
boundary. A focused forced-checkpoint probe must verify continued hover,
unsaved headers, framing, and shutdown on the same client connection.
Gary approved idle exec checkpoints with the 64 MiB growth budget on
2026-10-28. Implement this revision before submitting phase 1.

1. `commands/lsp/`: `main.x` (identity, `--help`, exit), `lsp.x` (framing,
   dispatch, positions), `analysis.x` (workspace state, unit lifetime,
   exports), and one file per feature group as they land. Manifest entry
   `lsp|experimental|Serve editors over the Language Server Protocol`.
   `README.md` following `commands/editor/README.md`.
2. VS Code: `etc/vsc-extension` adds `vscode-languageclient` and starts
   `x2c lsp` from `extension.js` with the existing `compilerPath` and
   `arguments` settings as `initializationOptions`. `semantic.js`, the
   snapshot directory, and process-group cancellation go away.
   `semantic.test.js` is replaced by a client start test;
   `providers.test.js` keeps the range tests that still apply. The legacy
   `workerPath` setting and `tools/x2c-editor` stay until phase 4.
3. Documentation: `docs/src/reference/cli.md` gains a "Language server"
   section before the VS Code section with the start command, settings,
   and this Neovim snippet as proof of editor independence:

   ```lua
   vim.api.nvim_create_autocmd("FileType", { pattern = "x2c",
     callback = function(ev)
       vim.lsp.start({ name = "x2c", cmd = { "x2c", "lsp" },
         root_dir = vim.fs.root(ev.buf, { "x2c.toml", ".git" }),
         init_options = { arguments = {} } })
     end })
   ```

4. Retirement: after the extension release that uses the client, remove
   `commands/editor`, its manifest row, `tools/x2c-editor`, the `workerPath`
   setting, and the `x2c editor` text in `cli.md`; `ProjectBuild.owning_target`
   keeps its one remaining caller.

## Validation

Phase 1 focused evidence (2026-10-28): command smoke and paced protocol tests,
legacy editor tests, extension tests and grammar suites, and VSIX packaging
passed. The final optional checkpoint workload crossed the real 64 MiB budget
twice, preserving PID, stdio, unsaved source/header/manifest state, hover,
definition, and once-only initialization/notices. Descriptor counts remained
six, and all observed helpers exited after shutdown. RSS was 322,752 KiB warm,
480,416 KiB maximum sampled, and 191,152 KiB settled. Cold hover took 0.823
and 0.879 seconds under concurrent host activity; these are observations, not
an isolated performance benchmark. No full gate ran in the implementation
session. The shared integrator owns publication validation and generated
artifacts. Manual VS Code and Neovim sessions remain unperformed.

- `commands/lsp/tests/run.sh`, run by `make commands-check`, drives
  `builds/0/libexec/x2c-lsp` with frames written by a `frame` shell
  function (`printf` body to a file, `wc -c` for the length). It sends
  `initialize`, `initialized`, `didOpen` with an unsaved text that differs
  from the disk file, `hover`, `definition`, a `didChange` introducing a
  parse error, `shutdown`, and `exit`, then checks with `grep` that the
  responses carry the expected ids, the hover text `int value(void);`, a
  `publishDiagnostics` with code `parse`, and that the process exited 0.
  Phases 2 and 3 extend the same script with completion, documentSymbol,
  references, rename, and semanticTokens checks. The script uses its own
  temporary and cache directories, as the editor test does.
- Extension: `npm ci && npm test` in `etc/vsc-extension` (not gated).
- Manual: open `src/` in VS Code and in Neovim with the snippet; confirm
  diagnostics, hover, and definition on `src/frontend.x`.
- Publication: `tools/gate-state.py ensure agent-pr-check` for every phase
  (commands change the validated tree). No performance checkpoint: no
  compiler hot path changes.

## Phases and size

| Phase | Content | Size |
| --- | --- | --- |
| 1 | server with initialize, sync, diagnostics, definition, hover; `owning_target` move; `SourceView.unset`; VS Code client; docs; smoke test | about 600 lines of x2c, 150 lines of JavaScript, 60 of docs |
| 2 | completion, documentSymbol, workspaceSymbol | about 250 lines of x2c |
| 3 | references, rename, semantic tokens | about 300 lines of x2c |
| 4 | retire `commands/editor`, `tools/x2c-editor`, `workerPath` | deletion only |

Each phase is one publication. Phase 1 ships before 2 and 3 are started
because the extension switch is the only user-visible risk; phases 2 and 3
are independent of each other.

## Plan review

Facts established elsewhere and relied on, not rechecked: the frontend
owns parsing, binding, diagnostics, and source facts; `SourceView` owns
overlay identity; `ProjectBuild.plan` owns target selection; `Frontend`
unit nesting is the stated lifetime contract, and the one-open-unit rule
follows it instead of adding a second lifetime scheme; `Json.parse` and
`Var.json` own JSON validity; `Content-Length` is checked once by reading
exactly that many bytes.

Reuse and deletion: the feature code is the body of `editor.x` behind an
LSP framing instead of argv; `_project_target` moves to one owner;
`definition_rows`, `mark_completion`, `source_occurrences`, and
`Tokenizer.scan` are called as they are. Phase 4 deletes the editor
command, the compatibility launcher, `semantic.js`, and its snapshot
protocol. New lasting mechanisms and why: the `Analysis` export (results
must outlive a closed unit), the read-set invalidation (the compiler offers
no finer unit of change), the stdin drain (cancellation and burst
coalescing without threads), and `SourceView.unset` (closed documents must
read disk again). No new cache beyond the exported records; no index built
in the background.

Idiomatic x2c: Map literals and `Var.json` build messages; `match` reads
compiler rows; isolated frame parsing and retained-unit or server dispatch;
no JSON-RPC framework, no handler registry object, no abstract transport.
Dispatch is one `switch` on the method String.

Validators and negative fixtures: the smoke test's parse-error document
protects diagnostic delivery; the malformed-frame `-32700` reply protects
the stream against a client bug; the unsaved-CPP refusal keeps the
existing message. No other dedicated diagnostics.

Last implementation step for each phase: review the completed authored
diff for repeated facts, unused machinery, and reuse missed above, fix what
it finds, then run the publication validation.
