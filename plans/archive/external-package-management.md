> Status: done
> Implemented on 2026-10-16 in `7c5848089`, with final publication artifacts
> and validation recorded by the delivering change.
> Package and CLI probes passed. The package suite now runs once through
> the existing command check, with scratch files outside unittest/build.

# External package management

## Result

Move package management out of the compiler into one shipped command,
`commands/package/`, built as `x2c-package` by the existing command framework.
Keep `x2c install`, `x2c remove`, and `x2c list` working with their existing
options, response files, help, output streams, and exit statuses.

Project builds still install their declared dependencies automatically.
The build passes dependency requirements to the package command and waits
for its exit status. The command owns package resolution and `x2c.lock`.
No response document, RPC service, manifest reparser, or new package format
is needed.

The development install also copies matching shipped commands through
`etc/x2c-payload.x`; `build-install` builds commands before copying the compiler.
The prefix installer and development installer share command-copy ownership.

## Current evidence

- `src/install.x` owns fetching, digest checks, extraction, package markers,
  staging, locking, source builds, installation, removal, and listing.
- Its `_build_source` already invokes the compiler's `translate` and `build`
  commands. It does not need in-process parsing or semantic state.
- `src/project.x:_resolve_dependencies` owns lockfile orchestration and calls
  `require_package`, `install_rows`, and `install_version`. These calls are
  the coupling to remove.
- `src/main.x` dispatches the three public commands after `CliRequest.parse`.
  That parser also owns their response-file expansion and help.
- `Compiler.driver_executable()` already finds and checks the matching
  compiler for an external command. The installer currently uses
  `x2c_get_executable()`, which would incorrectly name the package executable
  after extraction.
- `unittest/probes/run-package-install.sh` covers public operations,
  installed-home behavior, project pins, lockfile replay, and lock release.
  Its scratch home currently copies the compiler but no external command.

These are source observations, not results from an extraction prototype.

## Ownership and command interface

### Public compatibility

Retain the three command names, their option tables, and help in `cli.x`.
Replace their execution arms in `main.x` with dispatch to the same resolved
`x2c-package` executable, forwarding a canonical argument vector from the
validated request. This is the only compatibility layer.

For example, `x2c install -q --index INDEX NAME` becomes a package invocation
with operation `install`, `--quiet`, `--index INDEX`, and `-- NAME`.
Forward `--sha256` and `--force` when present. Removal forwards quiet and
its operand; listing has no operands. Preserve option acceptance and failure
statuses, including help succeeding without an installed command.

The package command parses its operation and small option set with the
existing `Args` facilities. It does not expand response files. The legacy
entry points have already expanded them, and forwarded values must remain
literal, including values beginning with `@` or `-`.

Register `package` as shipped. `x2c package install`, `remove`, and `list`
use the same implementation; their arguments follow the ordinary external
command rule of no implicit response-file expansion. Document the existing
short forms as the primary user interface. Do not add a generic command-alias
framework or three separate package executables.

The compatibility dispatch resolves the command in the compiler's libexec
location, never PATH, and supplies the existing `X2C_HOME`, `X2C`, and
`X2C_IDENTITY` environment contract. Reuse the existing dispatch operations
with only the small factoring needed to share resolution and environment
setup. Missing or mismatched commands produce an actionable error and stop;
there is no built-in installer fallback.

### Build dependency preparation

Use one private operation, with an ordinary argv vector:

```text
x2c-package ensure --lock /absolute/project/x2c.lock [--index INDEX] [--quiet] -- NAME VERSION NAME VERSION ...
```

The project reader already knows the dependency pairs. Pass them in their
current declaration order. Retain the caller's working directory so relative
index and archive paths retain current meaning. The lock path is absolute.
Use the existing child-process execution facilities without a shell.

The operation reads the existing six-field lockfile, checks installed package
versions, resolves missing rows through the selected index, installs missing
packages, and publishes the lockfile with the existing file operation.
It preserves the current fast path: satisfied pins and installed versions
cause no index access, network access, or lockfile rewrite. A recorded pin
reinstalls from its recorded archive and digest, even if the index changes.
Do not turn this extraction into a dependency solver or change transaction
semantics across multiple installations.

Successful preparation returns zero. Failure returns the existing package
failure status and prevents translation/native build work from starting.
Diagnostics and receipts retain their existing streams. The driver does not
parse stdout or read package metadata after success.

Keep the existing early return for editor source views and dry runs. They
must not invoke preparation. With no dependency declarations and no lockfile,
return without invoking the command. With no declarations but an existing
lockfile, invoke `ensure` with zero pairs; the package command removes the
obsolete lockfile as the build does today. The driver only checks its existence;
it does not parse or interpret lockfile rows.

This introduces one child process for an ordinary dependency-bearing project
build, including a satisfied build. Accept that simple boundary initially;
measure its cost using the existing performance workflow. Do not add a second
metadata reader or a persistent process to avoid the launch speculatively.

### Code placement

Move the implementation from `src/install.x` into `commands/package/` and
replace its `CliRequest` dependency with a small command-owned options record.
Move lockfile reading, row matching, installed-version checks, and lockfile
writing out of `project.x` into that command. Retain project dependency parsing
and ordinary installed-package search paths in the compiler.

Delete the old installer entry points and includes. Keep no second copy of
package-index parsing, marker interpretation, or installation state in `src/`.
The shared compiler archive may supply existing environment and utility
services; do not create a separate archive or a new stable compiler API.

Use `Compiler.driver_executable()` for source-package child builds. Preserve
compiler identity/version checks, current source-versus-bundle behavior,
staging cleanup, package-home locks, and release of locks before running the
user's program. Child source builds pass explicit inputs as today and must
not recursively prepare the caller's project dependencies.

## Implementation and delivery

Implement as one coherent change:

1. Move package operations and dependency preparation into the command.
   Add its entry point and shipped manifest row. Preserve existing formats
   and behavior while removing compiler-side owners.
2. Add the public compatibility dispatch and the single build preparation
   call. Reuse command environment setup and process execution. Keep command
   construction free of shell quoting and response-file reinterpretation.
3. Adapt installed-home fixtures and release/install packaging to include
   the shipped command through the existing manifest mechanism. Preserve
   building the compiler and command from a clean checkout without requiring
   the package command to build itself. Dependency-free compiler builds must
   not depend on command availability.
4. Relocate package-specific test execution into the existing command smoke
   test where needed, keeping each scenario executed once. Inspect current
   check ordering before moving any invocation. Do not add a second full
   package suite or expand/reorder recurring gates without Gary's approval.
   Keep CLI help and dispatch compatibility checks in their existing owners.
5. Update CLI/package documentation and relevant compiler ownership docs.
   Review and fix the complete authored diff before publication validation.

Implementation delivery follows the root repository instructions. This plan
adds no new recurring check, planning phase, or commit requirement. Final
bootstrap artifacts are regenerated by the existing publication command,
never hand-edited. The implementation request authorized direct delivery.

## Validation

Reuse the package installation probe and its fixtures for source directories,
archives, digests, bundles, force, indexes, damaged markers, safe removal,
listing, source meta modules, project pins, and lock release. Adapt scratch
homes to contain the matching shipped package executable.

Extend those existing scenarios only where the process boundary changes:

- Legacy help, options, response files, literal forwarded operands, stdout,
  stderr, quiet receipts, and exit statuses remain compatible.
- A first project build prepares dependencies; a satisfied build succeeds
  with the index unavailable and leaves the lockfile unchanged. Reinstallation
  uses the locked archive when an alternative index offers different content.
- Editor requests and dry runs do not invoke the package manager. Removing
  all pins removes an old lockfile. A clean dependency-free build succeeds
  when the external command is absent.
- Missing/mismatched commands stop dependency-bearing builds clearly.
  A package failure stops the build, and a successful `run` holds no package
  lock while executing user code.
- Source packages invoke the matching compiler, not the package executable.
  Verify installed-prefix use as well as checkout dispatch.

Run focused checks during implementation, then the existing publication gate
for the final integrated code tree. Use the existing performance checkpoint
for this build-orchestration change, with attention to satisfied dependency
builds; do not claim speed or binary-size improvements without measurements.

## Design review

The package command owns all package mutation and metadata interpretation.
The compiler keeps project syntax, installed import lookup, and compatibility
parsing. That small retained parser preserves a shipped contract without
retaining the installer. One argv request plus an exit status gives builds
all they need; no returned package graph or versioned protocol is justified.
The existing index and lock formats remain authoritative. Validation targets
observable compatibility and the new process boundary, rather than adding
validators for facts the project parser already established.
