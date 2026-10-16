> Status: done
> Implemented on 2026-10-16 in `de9bbc8b`, integrated with current dev.
> Focused semantic and transport checks passed; publication validation is
> recorded with the delivery commit.

# External editor adapter

## Result

Move the one-request editor adapter from `src/editor.x` into the shipped
`x2c-editor` command. Keep `x2c editor` working with the same private arguments,
response file, semantic results, and exit statuses. Existing VS Code settings
and the legacy worker launcher continue to work without changes.

The command owns request decoding, overlay loading, project target selection,
query selection, and response serialization. The compiler continues to own
parsing, binding, types, diagnostics, source facts, and source lifetimes.

## Evidence and decisions

- `src/editor.x` already confines the adapter to one source file. It calls
  `Frontend`, `ProjectBuild`, `SourceView`, and ordinary compiler operations.
  Move those calls with the adapter; retain their implementations in `src/`.
- `src/main.x` handles `editor` before ordinary external dispatch. `editor`
  is not a `CliRequest` built-in. Removing that special branch lets the
  existing dispatcher find and execute `x2c-editor` without another alias.
- Use the existing `execv` dispatch, which replaces the driver process.
  Preserve the editor service's process-group cancellation and child cleanup.
  Do not introduce a waited wrapper, daemon, RPC connection, or persistent cache.
- Initialize the command with `x2c_initialize_command_environment` and its
  embedded compiler identity, as other commands do. Reuse the dispatcher's
  `X2C_HOME`, `X2C`, and `X2C_IDENTITY` environment. Meta helper compilation
  already calls `Compiler.driver_executable()`; it must use the matching
  compiler, not attempt to run the editor command as a translator.
- Build against the existing compiler archive through `make commands`.
  Mark `editor` as `shipped` in `commands/manifest.txt`. Existing stage,
  development-install, prefix-install, and distribution assembly then carry
  the matching executable. No separate editor build system is needed.
- Keep the protocol private. Metadata before `--` remains literal argv;
  only the trailing build/translate configuration uses `CliRequest.parse`
  and its response-file expansion. Do not parse the transport with `Args`.
- Preserve the dedicated JSON response file, including source texts used for
  byte-to-UTF-16 conversion. Macro stdout and stderr remain separate.
  Serialize while `ParsedUnit` and its context are alive, then close them.
- Preserve status zero for a written semantic response, including source
  diagnostics, and status two for rejected or failed requests. Preserve
  dirty native-CPP rejection, manifest target selection, and the existing
  rule that editor requests do not install packages.
- A missing command uses normal external-command lookup failure. An identity
  mismatch uses the existing command initialization diagnostic. Neither case
  falls back to a second implementation. The editor client already reports
  compiler setup failures without fallback.

## Implementation

1. Move `src/editor.x` to `commands/editor/editor.x`. Add a small `main.x`
   that initializes the command environment and calls `editor_request`.
   Recognize standalone `--help` and `-h` before request decoding, so
   `x2c help editor` works. Do not inspect help-like words inside metadata.
2. Remove the editor include and special entry branch from `src/main.x`.
   Add the shipped manifest entry and a command README describing the private
   transport and shared semantic owners. Confirm that adapter objects no
   longer enter the compiler executable or compiler archive.
3. Update installations assembled by tests. In particular,
   `unittest/probes/run-package-install.sh` must copy `x2c-editor` into its
   private home's `libexec/x2c` directory before testing editor requests
   without the package command.
4. Preserve `tools/x2c-editor` as the legacy launcher and optional test entry.
   Document `make commands` as its prerequisite. Update its README, the CLI
   book's editor section, and the repository owner map to name the command.
   Keep extension discovery, settings, transport, and response handling intact.
5. Fit the command into the existing smoke-test convention without expanding
   the recurring semantic workload. Relocate the existing editor/meta-helper
   request assertion from `run-meta-helper.sh` into the editor command smoke,
   including its helper-cleanup assertion and required fixture setup. Keep
   unrelated meta-helper checks where they are. Keep the Node suites optional;
   do not add Node or another broad suite to publication prerequisites.
6. Review and fix the completed authored diff before publication validation.
   Check ownership, argument boundaries, unit lifetime, cancellation, test
   duplication, and command packaging. Generate bootstrap and documentation
   through their normal targets; never edit generated files by hand.

## Validation

Use existing tests for the semantic behavior. Run
`make -C tools/x2c-editor test` after building commands; this exercises both
`x2c editor` and the legacy launcher. Run the same worker suite with
`X2C_EDITOR_WORKER` pointing at the built `x2c-editor` executable and
`X2C_EDITOR_COMPILER` unset to verify direct command startup.

These tests cover unsaved primary and included sources, lexical definitions,
hover, retained and discarded macro declarations, diagnostics and recovery,
manifest package settings, and dirty native-CPP behavior. Run the extension's
existing semantic and provider tests for byte/UTF-16 spans, setup failures,
stale-result rejection, and process-group cancellation. These are focused
implementation checks, not new recurring gates.

Verify the extraction boundaries with bounded probes:

- Compare driver and direct-command responses for the same request, including
  a metadata path containing spaces and a literal `@` prefix. Check trailing
  compiler response-file expansion separately.
- Run the relocated meta-helper smoke and the package installation probe.
  Verify helpers terminate and an editor request succeeds with the package
  command absent.
- Exercise a staged prefix and the development installation with a semantic
  request and `x2c help editor`. Confirm the matching editor binary is shipped.
- Confirm missing and mismatched commands remain setup failures, using the
  existing external-command failure behavior and no protocol fallback.

Inspect the rebuilt compiler/archive membership to confirm removal of the
adapter. A source move alone is not evidence that the executable excludes it.
No compiler-throughput improvement is claimed by this plan.

## Delivery

Implement as one coherent change. Follow the root `AGENTS.md` delivery mode
and existing publication validation, including bootstrap regeneration and
self-host checks through `tools/gate-state.py ensure agent-pr-check`.
Archive this plan with the delivered revision. Implementation was subsequently authorized. Delivery follows the root
repository instructions.

## Plan review

The frontend produces semantic facts; the command reads them without a second
parser or semantic validator. `SourceView` establishes overlays, `ParsedUnit`
owns their analysis lifetime, and the command initializer establishes compiler
identity. The design reuses those boundaries without duplicate checks.

The change deletes the compiler's adapter entry and relocates its existing
implementation. The only new lasting entry code is the normal command `main`;
the manifest and existing build/install framework supply packaging. Ordinary
x2c calls preserve the current implementation without a new abstraction layer.

No new validator or dedicated failure diagnostic is proposed. Existing request
shape checks protect the argv boundary; existing native-CPP rejection prevents
analysis of saved text presented as unsaved text. Focused missing/mismatched
command probes protect deliberate setup-failure behavior. The recurring editor
smoke relocates existing coverage rather than adding a second semantic run.

## Implementation evidence

The nine worker tests passed through the driver, legacy launcher, and direct
command. All 11 extension semantic/provider tests passed. Driver, command,
and staged-prefix responses matched with literal metadata and compiler
response-file arguments. Missing and mismatched commands failed as expected.
The relocated helper-cleanup smoke passed. The rebuilt compiler and shared
archive contain no editor adapter symbol or object.
