# The scripting library gap

> Status: active - 2026-09-16. Phase A done; phases B, C, and D remain.
> Second of four plans from the 2026-09-15 capabilities and market spike.
> The scripting capability shipped 2026-09-15 and the repository still runs
> 30,212 lines of Python, shell, and awk automation against it.

## The result

A script does the work scripts actually do without leaving x2c. Each phase
ships the primitives one real conversion needs and converts that tool, so no
operation lands without a consumer.

Regex is not implemented. `lib/match.x` is structural List matching and
`String.glob_match` is shell globbing; a text engine is greenfield, and
`packages/pcre2` already ships 34 operations with named captures. Because
`CliRequest.package_roots` (`src/cli.x:1132-1136`) always appends the x2c home,
`x2c install pcre2` then `import "pcre2"` works in a script with no flags.
That is a documentation task, not a code one.

## Phase A - the primitives a shell script needs (done)

Grounding the phase in `tools/check-*.sh` rather than in the spike's capability
list shrank it considerably. Those scripts need exactly two operations that did
not exist:

| Operation | Where | Replaces |
| --- | --- | --- |
| `String.is_executable` | `lib/path.x` | the shell's `-x` |
| `String.env` | `lib/process.x` | `${VAR:-default}` |

Everything else they do was already covered. `cd` is unnecessary because
`List.options` takes `dir:`; exporting for a child is unnecessary because
`options` takes `env:`; `mktemp -d`, `find`, `sort`, `cmp`, and `rm -rf` are
`String.temp_dir`, `String.glob`, `List.sort`, `read_text`, and
`String.remove_tree`.

`tools/check-release.sh` became `tools/check-release.x`. Both versions were run
against the live site for 0.13.0: identical stdout and identical exit status,
on the success path and on a wrong-version failure.

**`lib/time.x` was deferred, not delivered.** No script in this phase reads a
clock, so shipping a time module here would add an owner with no consumer,
which the bloat test in `agents/x2c-philosophy.md` rejects. It belongs in the
phase whose conversion needs it; `tools/agent-failure.py` and the benchmark
tools are the real consumers. Note that `lib/time.x` generates a `time.h`,
which is why `plans/x2c-include-prefix.md` landed first.

**Not converted, deliberately.** `tools/check-conformance-coherence.sh` and
`tools/check-generated-stages.sh` run inside the Makefile's gate path
(`Makefile:207-220`). Rewriting them in x2c would put the check that detects a
broken compiler behind the compiler's own scripting feature. They stay shell.

## Phase B - `lib/args.x`

Argument parsing from a declarative spec, returning a `Map`. Unblocks 17 of the
repository's 21 Python tools. `src/cli.x` supplies the spelling conventions
(attached values, `--opt=value`, `--`, `@response`) and nothing else; its
engine is welded to `CliRequest` and a Symbol `switch` and is not extractable.
Proof: convert `etc/x2c-payload.py`, which needs only argument parsing and
path operations.

## Phase C - `lib/json.x`

`String.parse_json` returning ordinary `Map`/`Array`/`String`/number/null
values, and `Var.json` writing them back, matching the converting surface
`packages/yyjson` already exposes so a script can move to the package for order
and duplicate fidelity without rewriting. `lib/scan.x` supplies scalar scanning
(`scan_number_typed`, `scan_c_string_status`); `lib/tokenizer.x` is x2c/Lisp
specific and is not reusable. This should consolidate the two duplicate JSON
string escapers at `src/editor.x:27-36` and `src/build.x:521-529` rather than
becoming a third. Proof: convert `tools/check-gallery-examples.py`.

## Phase D - `lib/digest.x`

SHA-256 over `String` and `File`: `String.sha256` hashes text and
`File.sha256` hashes the raw bytes remaining in a stream, each returning the
lowercase hexadecimal `String` that `shasum -a 256` prints. Proof: `_verify`
in `src/install.x` calls `File.sha256` instead of running `shasum` or
`sha256sum`, so verifying a package download no longer needs a host tool.
`unittest/probes/run-package-install.sh` covers the matching and mismatched
digests.

Two changes from the original phase. CRC32 is dropped because nothing
consumes it. `tools/gate-state.py` is not the proof: it is the publication
gate, and gate-path tooling must not depend on the scripting feature it
validates.

The file entry point is a `File` method, not a path method. A `String`
receiver already means text for `String.sha256`, so a path spelling would need
a second name; `File.open(path, "rb")` with `$auto` is the path form, and a
`File` also hashes a pipe or an already-open stream.

## Module placement

Each new module goes in `OPTIONAL_SOURCES` (`lib/Makefile:7-10`) and reaches
scripts through `lib/scripting.x`, which `src/frontend.x:96-102` puts in place
of the shebang line. Prelude membership is not free: every translation
replays the prelude's per-unit `.xi` interfaces, and `process.xi` alone is
41,860 bytes.

Unused modules cost nothing in a binary. There is no `--gc-sections` anywhere;
the archive is a plain `ar rv` and the linker pulls members only to resolve
undefined symbols, so twelve of the current `lib/*.o` are absent from a 405 KiB
example binary. Linkage is all-or-nothing per `.x` file, so keep each module
small.

## Defect found during Phase A

`exit(3)` inside a script unit aborts with status 134 and prints
`x2c error floor: ... Error.pop out of order`, because C `exit` skips the
exception frame that `src/compiler.x:1539-1563` wraps around the synthesized
`x2c_script`. The same call in a program with `main` exits 3, and `return 3` in
a script exits 3. Either the synthesized main should tolerate it or the
language reference should say `return` is the only way out of a script unit.

## Validation

`make verify` and `tools/gate-state.py ensure agent-pr-check`. Each phase's
converted tool is its own end-to-end check: run the old and the new version and
compare output and status.

## Plan review

- **Facts already established.** `Scope` allocation, `%[]`, and `%{}` do not
  return null, so new modules add no allocation checks. `File.fileno` is
  already a public boundary. `String.env` returns NULL for an unset name, which
  is the documented absence case, not a failure.
- **Reuse and deletion.** Phase A deleted a shell script rather than adding
  beside it. Collapsing `src/build.x:1053` and `src/utils.x:166` onto
  `String.is_executable` was considered and declined: neither file includes
  `path.x`, and `src/main.x:181` tests `W_OK | X_OK`, which the method does not
  express. Phase C should delete one of the two JSON escapers.
- **Why these are owners.** Argument parsing, JSON, and digests are three
  concerns with three test surfaces, which is the split test in
  `agents/x2c-code-organization-guide.md`. `is_executable` and `env` went to
  existing owners instead of a new `lib/os.x` for the same reason.
- **Validators and fixtures.** Phase A added two unit tests and no validators.
  The `is_executable` test asserts that a directory qualifies, which pins the
  documented `-x` semantics against a later narrowing. A malformed JSON
  document is user input rather than an established fact, so Phase C's parser
  needs a real diagnostic; that is the only new failure surface these phases
  propose.
