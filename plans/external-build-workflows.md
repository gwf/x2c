> Status: active
> Implementation in progress. Delivery is one shared-integrator submission.

# External build, run, and script workflows

Keep `x2c build`, `x2c run`, and `x2c script`, implemented by one shipped
`x2c-build`. Direct invocation accepts the same operation followed by its
ordinary options. Script-language parsing and entry construction are unchanged.

## Ownership

- `src/translation.x` owns synchronous translation, inspections, workers,
  ordered diagnostics, and signal forwarding. `translate_request` accepts the
  existing `CliRequest`, optional per-input output directories, and an optional
  parent-process callback for starts and successful completions. It neither
  reads nor writes build state. Ordinary translation retains its reports.
- `commands/build/` owns target building, native actions, run execution, script
  cache locking, freshness, publication, pruning, and final process replacement.
  Command and target contexts retain their original lifetimes.
- `src/project.x` retains manifest parsing and planning for build and editor.
  Shared utilities own the cache root. Native toolchain primitives stay shared.
- The CLI tables remain the syntax authority. The driver reads initial
  arguments, then forwards that exact vector through `--driver-arguments`.
  The command parses it without repeating initial response-file expansion.
  Direct invocation uses the ordinary reader and parser.

## Bootstrap and identity

Each numeric stage archives its compiler objects except `main.o`, generates
its embedded identity, translates the command using its own `translate`, and
links `libexec/x2c-build` with native Make rules. Other commands reuse that
archive and identity. Their ordinary build loop excludes `build`.

External commands derive the stage from the matching driver. Compiler identity
still determines interface and module compatibility. Build and script state
also hashes the build executable, captured once before command contexts open.
Native module actions explicitly name the loader: the matching driver for
application modules, and the current host for compile-time modules.

## Verification and delivery

Use existing CLI, native module, meta-helper, meta-cache, editor, and package
probes. Add a focused command smoke for direct invocation, exactly-once argument
reading, stage selection, command-only cache invalidation, and missing/mismatched
commands. Update hand-built installations that invoke workflows. Check clean
bootstrap recovery and a later self-host stage, development and prefix installs,
and distribution command presence. No new recurring gate is added.

Compare cold build, unchanged build, and warm script startup against the saved
baseline on the same quiet host. Record absolute times and investigate material
regressions. Review the authored diff and submit focused evidence. The shared
integrator owns final generated artifacts and the publication gate.

## Plan review

The CLI establishes argument meaning; the translation service consumes that
request and produces the existing artifacts. Build alone decides reuse and
native work. Existing manifest parsing, runtime services, and command packaging
are reused. The callback replaces direct `Build` calls. The private argument
mode prevents double expansion without serializing requests. Native stage rules
break the self-build cycle. The additional executable identity prevents stale
reuse after command-only edits. Explicit loaders preserve native linking.

No grammar, parser, persistent service, artifact registry, or fallback is added.
Operation rejection protects the standalone command's deliberately limited
public syntax. Existing input and identity diagnostics remain intact.
