# The scripting library gap

> Status: active - 2026-09-16. Phases A and B done; phases C and D remain.
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

## Phase B - `lib/args.x` (done)

Argument parsing from a declarative spec, returning a `Map`. `src/cli.x`
supplied the spelling conventions and nothing else; its engine is welded to
`CliRequest` and a Symbol `switch` and is not extractable.

| Operation | Contract |
| --- | --- |
| `Map List.parse_args(List args, List spec)` | parses `args`; every spec name is present in the result |
| `String List.usage(List spec, String program)` | synopsis, options, and described operands, help at column 30 as in `x2c help` |

A spec is a `List` of rows. A row that begins with dashed words is an option
with those spellings, named by its first long spelling without dashes, or by
its short one. A row that begins with any other word is an operand. The rest
of a row holds `(value placeholder)`, `(default value)`, `(help "text")`,
`required`, and `repeated`. Long options take `--name value` and
`--name=value`; short options take `-n value` and `-nvalue`, and short flags
share a word. Operands may interleave with options, `--` ends option
parsing, and operand rows take operands in spec order, a `repeated` one
taking the rest. A flag's value is its occurrence count, a `repeated` row's
is a `List`, and any other row's is its last `String`; an absent row holds
its default, or else zero, an empty `List`, or a NULL `String`, all falsy.
Bad input and an unreadable spec raise `<bad-arg>` with `why` and the
offending `option`, `operand`, or `spec` entry; nothing exits.

`etc/x2c-payload.py` became `etc/x2c-payload.x`. It is not on a gate path:
`install`, `uninstall`, and `dist` are outside `precommit`, `sanity-check`,
and `agent-pr-check`, and `ape-build` is a release-only target. Every caller
already needed a native `builds/0`: `install` and `dist` depend on `build`,
`uninstall` now does too, and `etc/cosmopolitan/build-ape.sh` compares
`bootstrap` with `builds/0` before the payload step, which in turn copied
`builds/0/lib/*.h` and `*.xi`. Each workflow that reaches these targets runs
`make build-safe` first. The two
versions were run side by side on `support` (with and without
`--licenses`), `install` with and without `--destdir` (including an empty
one), reinstall, `uninstall` with and without an unowned file, an unowned
target, a relative prefix, and a missing installation: identical stdout,
identical status, and identical trees by path, mode, content, and mtime,
apart from the three files written at run time. `make install PREFIX=`,
`make install DESTDIR=`, `make dist`, and `make uninstall` produced
identical output, installed file digests, and tarball listings; `make
uninstall` adds only the `build` prerequisite's banner. Argument
misuse still exits 2 but prints the generated usage instead of argparse's.
A warm run takes 0.11 s against Python's 0.56 s.

Decisions a reviewer should check:

- **Rows are a `List`, not a `Map` of `Map`s.** `Map` iteration order is not
  source order, which the usage text needs, and bare words inside `%()` are
  exact `Atom`s, so a long option such as `--no-phony-deps` keeps its full
  spelling where a compact `Symbol` key would truncate at ten characters.
- **Result keys are `String`s.** `Symbol` keys would truncate the same long
  names; `options["dry-run"]` reads directly.
- **Every name is present, and values stay `String`s.** A `void` `Map` read
  raises on a truth test, so an absent flag is zero and an absent value a
  NULL `String`. Converting to a number is left to the caller rather than
  adding a type column to the spec.
- **A non-repeated option given twice keeps the last value**, as `getopt`
  programs and argparse do; a flag counts instead, so `-vv` is 2.
- **No automatic `--help`.** Parsing raises instead of exiting, so a script
  that wants `--help` beside `required` rows catches `<bad-arg>` and prints
  `List.usage`. The rejected alternative, a built-in help row that
  suppresses `required` checks, special-cases one name.
- **Subcommands are not a spec feature.** The payload tool dispatches on its
  first word and parses the rest with that command's spec.
- **Not supported:** `@response` files, which the plan listed among
  `src/cli.x`'s conventions, have no consumer yet; abbreviated long options
  are rejected as unknown.

## Phase C - `lib/json.x` (in progress)

The module is built and registered as an optional module. A script includes
it with `#include "json.x"`; `lib/scripting.x` does not. The tool conversion
waits for `lib/args.x` and `lib/digest.x`.

| Operation | Result |
| --- | --- |
| `Json.parse(String)` | the value of JSON text |
| `Json.read_file(String path)` | the value of a JSON file |
| `Json.write_file(Var, String path)` | writes compact JSON text |
| `Var.json(Var)` | compact JSON text |
| `Var.pretty_json(Var)` | JSON text indented two spaces per level |
| `Json.bool(int)` | the JSON `true` or `false` value |
| `Json.is_bool(Var)` | whether a value is a JSON boolean |
| `Json.boolean(Var)` | 1 or 0; `<bad-types>` for a non-boolean |

An object is a `Map` with `String` keys, an array an `Array`, a string a
`String`. An integer is an `int` `Var` when it fits, then `long`, then
`unsigned long`; every other number is a `double`. Null is the all-zero `Var`
the values guide calls `Null`. Booleans are `JsonBool`, a registered
`<jsonbool>` object tag over two static singletons, with `str`, `repr`, and
`truth`.

Decisions a reviewer should check:

- **Names follow the package, not `String.parse_json`.** The yyjson converting
  surface is `Json.parse`, `Json.read_file`, `Json.write_file`, `Var.json`,
  `Var.pretty_json`, `Json.bool`, `Json.is_bool`, and `Json.boolean`; this
  module has exactly those names. The package's `_opts` forms take yyjson
  flag types and have no counterpart. `String.parse_json` was rejected
  because it would not survive a move to the package.
- **`json.x` is opt-in (Gary, 2026-09-16).** A script writes
  `#include "json.x"`, and moving to the package replaces that line with
  `import "yyjson" with Json;`. This avoids a collision measured with the
  module in `lib/scripting.x`: the script unit then declared `Json` and
  `Var.json`, so `import "yyjson" with Json;` failed with
  `package name 'Json' collides with a declared name`, and `value.json()` on
  a package value resolved to this module, because ordinary methods come
  before imported ones, and raised `<bad-types>` on the package's
  `<yyjson--bo>` booleans. No C symbol collides either way.
  Rejected: including it automatically with the yyjson names, which forces
  every script that uses the package through its alias
  (`yy.Json.parse`, `yy.Var_json`); and including it automatically with
  distinct names such as `String.parse_json`, which removes the collision
  but makes a move to the package a rewrite of every call. The switch still
  changes integer families and the malformed-input cause, as the next items
  record.
- **Integers match x2c literals rather than the package.** yyjson boxes every
  integer as `<llong>` or `<ullong>`. `Var.equal` does not equate integer
  families, so `<llong>` 5 never equals the literal 5 in `%{n: 5}`; parsing
  to `<i32>` and `<long>`, as the compiler types literals, keeps parsed
  values equal to written ones.
- **Output sorts object names.** A `Map` has no insertion order, so the
  package writes the `Map`'s iteration order. Sorting by name makes equal
  values produce equal text, and the pretty layout is Python's
  `json.dumps(value, indent=2,
  sort_keys=True)`, which `tools/gate-state.py`, `tools/repo-metrics.py`,
  `tools/harness-metrics.py`, and `packages/tools/deps.py` already write.
- **Every rejected document raises `<bad-arg>`, unlike the package.**
  Syntax, nesting past 512, a number beyond `double`, an unpaired surrogate,
  invalid UTF-8, and
  `\u0000` all carry `why`, `offset`, `line`, and `column`, plus `path` from
  `Json.read_file`. `<malformed>` is the compiler's recovery cause, and the
  package's split between `<malformed>`, `<size-limit>`, and `<bad-enc>` would
  make a script catch three causes for one kind of bad input. No cause was
  added.
- **Writing accepts `Symbol`s.** `Symbol` keys and values are written as
  strings, because bare `%{}` literal keys are `Symbol`s; the package rejects
  them. NaN and infinities raise `<conv-range>`, strings that are not UTF-8
  raise `<bad-arg>`, other unsupported tags raise `<bad-types>`, and nesting
  past 512 (including a cycle) raises `<size-limit>`.
- **Repeated names keep the last value**, as in the package's `to_x2c` and
  in Python.

`lib/scan.x` supplies only `scan_ascii_digit` and `scan_next_line_col`.
`scan_number_typed` accepts a leading `+`, octal, hexadecimal, `.5`, `5.`, and
C suffixes, and `scan_c_string_status` accepts C escapes, so neither matches
JSON. The escapers in `src/editor.x` and `src/build.x` are being consolidated
by another change; the compiler does not include optional modules, so that
work cannot call this one.

**Evidence.** `unittest/test-json.x` has 10 tests and 170 assertions. A
one-off comparison, not wired into any target, parsed all 41 tracked
`*.json` files: 39 match Python's `json` module semantically, and byte for
byte in both the compact and sorted-pretty forms, and the two JSONC files under
`etc/vsc-extension/` are rejected by both parsers at the same line and
column. A differential run of 798,478 generated valid and corrupted
documents against Python's `json.loads` found no disagreement. The 4,528
documents Python accepts only through its extensions (NaN, infinities, a
number beyond `double`, an unpaired surrogate, or U+0000) are all rejected
here, and integers beyond `unsigned long` compare as `double`s.

**Consumer.** `tools/gen-package-index.py`, once `lib/args.x` and
`lib/digest.x` land: it reads `BUNDLE.json`, hashes archives with SHA-256,
parses arguments, and runs `tar` through `process.x`. Its only caller found
so far is `.github/workflows/release.yml`; confirm it is off the gate path
before converting. `tools/check-gallery-examples.py` was the first choice but
is also edited by open draft PR #59, and it would need the Markdown fence
reader from `tools/check-doc-examples.py` rewritten without regex.
`tools/agent-failure.py` needs `lib/time.x`.

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

## Defects found during Phase B

Fixed in this phase, because the payload conversion depends on them:

- **An empty argument truncated a child's argv.** An empty `String` is
  NULL, and both `_exec` in `src/script.x` and `_argv` in `lib/process.x`
  copied it into the argument vector, ending it early.
  `x2c script probe.x a "" b` gave the script only `a`, and
  `%(printf "[%s]" $empty x).output()` returned `[]`. `make install` passes
  `--destdir ""`. Covered by `unittest/test-process.x` and the script case in
  `unittest/probes/run-cli-boundary.sh`.

Found here and fixed separately on `main`: `include/Makefile` named its
header directory `PREFIX`, so a command-line `make install PREFIX=<dir>`
filled `<dir>` with symlinks, `make dist PREFIX=/opt/x2c` failed creating
`/opt/x2c`, and `make clean PREFIX=<dir>` ran `rm -rf <dir>`. The `make`
comparison above was run with that fix in place.

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
