# The agent feedback loop

> Status: active - 2026-09-16. Third of four plans from the 2026-09-15
> capabilities and market spike. The compiler half is implemented:
> `--max-errors`, declaration-granular parse recovery, and
> `--diagnostics-file` JSON Lines. Step 7, `llms.txt` and the single-file
> reference, belongs to a separate delivery and is not done here.
> Notes: the probe disproved the original recovery table. Raising the limit
> alone produced 174 cascade diagnostics across 115 fixtures, because resync
> started at the error token inside a body. It also exposed three reporting
> defects that the limit of one had hidden; all three are fixed here.

## The result

- `x2c translate foo.x` reports every independent error in the file's
  top-level declarations, up to a bound, instead of stopping at the first.
- `--max-errors <count>` sets the bound for `translate`, `build`, `run`, and
  `script`. The default is 20; 0 removes the bound.
- `--diagnostics-file <file>` writes the diagnostics as JSON Lines, one object
  per diagnostic, instead of standard error.
- Not in this delivery: `https://x2c-lang.dev/llms.txt` and a single-file
  language reference (step 7).

## What was already built

`Compiler.full_parse` (`src/compiler.x`) wraps top-level parsing in
`$let(c.recovery_depth, c.recovery_depth + 1)`, catches
`%(malformed (category ?category) *)`, resynchronizes with `_sync_top_level`,
and continues. `Compiler.report_error` (`src/diagnostics.x`) raises instead of
exiting whenever `recovery_depth > 0`. `Diagnostics` accepts any limit and
treats 0 as unlimited.

`Compiler.new` created every store with a limit of 1, so the loop's
`if (c.diagnostics.reached_limit()) break;` ran before resync on the first
error, and the recovery path had never executed.

## Probe

The limit was raised to 20 locally and two files were translated: one with
parse, type, and macro errors in separate top-level functions, and one with
the same three errors in one function.

The original table did not hold. `_sync_top_level` skipped forward from the
error token to the next `;` or balanced `}` at depth zero. Inside a body that
is the end of the failed statement, so the rest of the body parsed as
top-level declarations: every body error added `type: expected scalar type`
at each following statement and at the closing `}`. `make
verify-fixtures-update` changed 115 `.diagnostics` files, adding 174 such
lines. Three errors in one function also reported as several errors, not one.

The probe and the fixture review found three more defects that a limit of one
had hidden:

- `Compiler.parse_macro_definition` (`src/macros.x`) set `c.macro_holes` before
  parsing the signature and restored it only in a `defer` registered after
  the signature. A rejected signature left every later declaration parsing as
  a macro template, which skips type checks, so their errors were never
  reported. Reproduction: a `macro Expression $call(Expr $a..., Expr $b)`
  definition followed by `int f(int v) { return v is int; }` reported one
  error instead of two.
- `_report_lisp_failure` never cleared `macro_sdk_failure_message` outside a
  macro expansion. An SDK call such as `$(x2c.type.resolve ...)` in a function
  body left its message behind, and the next Lisp failure in another
  declaration, such as `$(import "missing.xlisp")`, reported that stale
  message at the new site.
- Two producers reported one failure twice. A failed protocol adoption is
  resolved by `Compiler.resolve_protocols` at the start of the parse and again
  when its declaration is parsed (`protocol-adoption-unresolvable`,
  `protocol-fallback-result-needs-reverse`). `_raise` in `src/transform.x`
  reported an invalid raise detail and then converted it to `Var`, which
  reported the same value again (`raise-invalid-object`).

## Recovery after this change

| Scope | Result |
| --- | --- |
| Parse, type, and macro errors in separate top-level declarations | Reported, in source order |
| Several errors inside one declaration | The first one. The declaration is skipped whole |
| A use of a rejected definition | Reported as its own error, for example an unknown macro or a type that is not iterable |
| Tokenize and symbol collection | One. `_shallow_parse_loop` has no per-declaration `try` |
| Transform, generate, emit | Unchanged: most errors still exit at the first report |

Symbol collection parses type declarations, so a syntax error in a
`typedef struct` stops the unit even when later functions also have errors. A
rejected macro or keyword definition during collection skips the rest of
collection (`_shallow_parse_compile_time_definition`), so full parsing then
reports a later type declaration's error too.
Sub-declaration recovery and collect-phase recovery remain separate projects.

## Decisions

**Default bound: 20.** No existing fixture reaches it; after the resync
change no fixture that predates this plan reports more than two errors. Clang
uses 20. A bound keeps a file with one systematic mistake, such as a missing
include, from reporting once per declaration for hundreds of lines; 0 is
available for tools that want everything. Rejected: 0 (unlimited) as the
default, as GCC and rustc do, because a long run of reports about one cause
costs a reader or an agent more than it tells them.

**Resync from the declaration start.** The recovery loop records the token
and brace-stack depth at the start of each top-level declaration. On a
`<malformed>` transfer, `_sync_top_level` rewinds to that token and skips the
declaration: it ends at `;` outside delimiters, or at a closing delimiter whose
next token begins a later line. The second rule ends function bodies and
`macro ... => (...)` definitions, which have no trailing `;`, while `} *Name;`
continues to its `;`. Rejected: resynchronizing from the error token, which is
the cascade above, and column-based heuristics, which depend on formatting.

**Doubled Lisp diagnostics.** `_eval_string` re-raises
`%(malformed (category ?category))` before its universal catch. A `<malformed>`
transfer means a compiler operation called from Lisp has already reported its
diagnostic; wrapping it in `compile-time Lisp evaluation failed` would report
a second one with an internal `(malformed ...)` note. `_report_lisp_failure`
consumes `macro_sdk_failure_message` before reporting it. Rejected: having
`_report_lisp_failure` compare the store's count before and after
evaluation, which needs saved state for a fact the error code already carries.

**Identical reports are stored once.** `Diagnostics.report` ignores an entry
structurally equal to one already stored. This removes the protocol adoption
duplicate at its only shared point. Rejected: suppressing the report in
`resolve_protocols` for the translation unit's own adoptions, which would lose
the error for any adoption whose declaration is not parsed again, such as one
replayed from a declaration bundle, and would need proof that none are. The
`_raise` duplicate is fixed at the producer by not converting a rejected
detail.

**Dependent reports are kept.** After the resync change six existing fixtures
gained one report each, all uses of a rejected definition:
`class-repr-signature`, `foreach-keyword-collision`,
`macro-deferred-free-index`, `macro-sequence-nonfinal`,
`macro-statement-hole-collision`, and `protocol-typedef-inherited-invalid`.
Each second report is accurate. Suppressing them needs a record of rejected
definitions consulted at every use, which this plan does not add.

**JSON destination: a file, not a stream.** `--diagnostics-file <file>` writes
JSON Lines to `<file>` instead of standard error. `src/editor.x` already
records why: compile-time Lisp and macros print freely to stdout and stderr,
and a stray partial line without a newline corrupts the next JSON line on a
shared stream. A file carries only diagnostics.

- `main` opens the file once, before dispatch, with `O_CREAT | O_TRUNC |
  O_APPEND | O_CLOEXEC`. A command with no diagnostics leaves it empty.
- `Compiler.print_diagnostic` is the only printer, both for the streaming
  emitter and for `_report_diagnostics`. With the descriptor open it formats
  one line in a `Buffer` and issues one `write`. `_translate_workers` forks
  after the open, so every worker shares one append-mode file description;
  each line is one append, so lines never interleave.
- `report_error` may `exit(1)` mid-stream. Each line is written when it is
  reported, with no stdio buffer, so the file is complete at exit.
- Driver, host preprocessor, C compiler, and linker failures are not compiler
  diagnostics and stay on standard error; the exit status reports failure.

Rejected: `--diagnostics=json` on standard error, because the stream is shared
with compile-time output; and writing JSON in addition to text, because the
text would duplicate every diagnostic for a tool, and a fixture could not
observe the file.

**JSON shape.** Keys in order: `code`, `message`, `severity`, `file`, `line`,
`column`, `length`, `position`, `notes`. `severity` is `warning` for
`<warning>`, `note` for the `<limit>` notice, and `error` otherwise. The five
location keys are always present and `null` without a location. `notes` is
the entry's String notes in order; text output joins them with spaces, and
some producers split a label and value into two notes.

**Path rendering.** Text shows a source under the x2c root relative to the
root and leaves other relative paths as given. JSON resolves each path against
the working directory, taking a relative path that does not exist there as
root-relative, then writes it relative to the working directory when the
source is inside it and absolute otherwise. A consumer resolves every `file`
against the directory it ran x2c in. Fixtures run from the repository root and
stay portable. Rejected: always absolute, which embeds the checkout path in
fixtures; and the text path unchanged, which is ambiguous whenever the working
directory differs from the root.

**One JSON string writer.** `report_json_string(Buffer, String)` in
`src/report.x` replaces `_string` in `src/editor.x` and `_json_string` in
`src/build.x`. `report.x` already owns output formatting and is included by
both. The editor now assembles its response in a `Buffer` and writes it once.

## Implementation

1. `src/cli.x`: `CliRequest.max_errors` and `diagnostics_file`; two
   `<general>` rows for `CLI_TRANSLATE | CLI_NATIVE`; `_driver_count` parses
   both `--jobs` and `--max-errors`; `_parse_command` defaults `max_errors` to
   20. `bootstrap_build_request` copies it.
2. `src/frontend.x`: `Frontend.start` sets the unit compiler's limit from the
   request. `Compiler.new` keeps 1; `Compiler.new_shared` inherits the owner's
   limit.
3. `src/compiler.x`: `_delimiter_step` and the declaration-start
   `_sync_top_level`.
4. `src/macros.x`: the `macro_holes` restore, the `<malformed>` re-raise, and
   the consumed SDK failure message. `src/transform.x`: no conversion of a
   rejected raise detail. `src/diagnostics.x`: identical reports stored once.
5. `src/diagnostics.x`: `diagnostics_write_json` and the JSON line writer;
   `src/main.x` opens the file after `cli_parse`.
6. `src/report.x`: `report_json_string`, used by `build.x`, `editor.x`, and
   `diagnostics.x`.
7. Deferred to another delivery: `llms.txt` and the reference bundle.

## Validation

- `diagnostics-recovery`: a rejected macro signature, a body parse error, a
  type error, a macro expansion error, and two errors in one function. It pins
  source-order reports, one report per declaration, and the `macro_holes`
  restore.
- `diagnostics-collect-stops`: a `typedef struct` syntax error followed by two
  function errors, pinning that collection stops at one.
- `diagnostics-json`: `.flags` with `--max-errors 2 --diagnostics-file
  /dev/stderr`, pinning the JSON shape, relative paths, and the `limit`
  notice as a `note` with null location fields.
- `unittest/test-diagnostics.x`: identical reports are stored once.
- `cli-translate.help`, `cli-build.help`, `cli-run.help`, and
  `cli-script.help` were edited by hand.
- `docs/src/reference/language.md` (Diagnostics) and
  `docs/src/reference/cli.md` (Compiler diagnostics) document the bound,
  recovery scope, and the JSON contract.

## Plan review

- **Facts already established.** `report_error` guarantees a raise under
  recovery, so the recovery loop does not test whether a diagnostic exists
  before resynchronizing. `_build_entry` guarantees the four rows, so the JSON
  writer does not test for them. It writes `null` for a `void` location
  field because an entry without a location, such as the `limit` notice,
  stores an empty location. The
  CLI rejects a negative bound, so the frontend assigns it without clamping.
- **Reuse and deletion.** No new recovery machinery: the existing loop now
  reaches its resync. Two JSON escapers become one. The JSON writer reuses
  `print_diagnostic`, the only printer, rather than a second emitter seam.
  `_driver_jobs` became `_driver_count` for both counts.
- **Why idiomatic.** The flags follow `--jobs` and `--compile-commands`. The
  destination is process state opened once in `main`, like
  `report_configure`. The resync reads token types and the brace stack the
  parser already maintains.
- **Validators and fixtures.** No new diagnostic codes. The `limit` notice
  already existed and becomes reachable. The structural duplicate check in
  `Diagnostics.report` prevents wrong output, a diagnostic printed twice. The
  three fixtures protect deliberate public behavior: which errors are
  reported together, the collect-phase boundary, and a machine-readable
  contract other tools parse.
