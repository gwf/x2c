# Deep review remediation (2026-11-02, second pass)

> Status: active - implementation and combined review underway on 2026-11-02.
> Gary selected direct delivery to `dev`. Starting revision:
> `87ced5324f15a2098bca98cee7500bb1a0f5b3b4`; review baseline:
> `6f537e429`. Worker repairs are collected on `codex/remediation-20261102`.
> Final publication evidence is recorded below when complete.

## Requested behavior

Repair what the 2026-11-02 second-pass review reproduced at `dev`
6f537e429: silent miscompilations, invalid generated C, runtime crashes
and wrong failures, tooling defects that block delivery, and repairs from
the 2026-11-01 batches that landed only partly. Then remove the verified
waste and settle the contracts the review found applied several ways.

## Decisions taken in this plan

- A macro's free name resolves at the expansion site through every
  binding form there, aliases included; the book's hygiene rule is the
  contract and the compiler is wrong.
- The region check treats an assignment of fresh storage to any outer
  binding as an escape, and an element read from a region-born container
  as region-born; it gets rows for `Array_getindex`, `Map_get`, `shift`,
  `take_last`, `del`, `remove`, the `.block()` views, the `write_str` and
  `write_repr` family into a Buffer, `Buffer.write_code_point`, and
  `MapSubInt`.
- A String operation that returns its input unchanged first passes it
  through one shared canonical-pool check, as `getslice` already does.
- Protocol `discard` applies to every temporary a protocol operation
  consumes, including `truth` in conditions and compound updates.
- `Regex.replace_fn` with a null `Func` follows the 2026-11-02 callback
  rule: it raises through `Func.apply` when a match needs it.
- `String.unescape` uses the C escape rules that `scan_c_escape_value`
  implements. Percent strings, Symbols, Lisp source, and strings nested in
  quoted collections retain their documented byte escape rules.
- A conditional whose arms are a String and a null literal boxes as a
  null String, not a pointer.
- Generated headers emit `struct tag;` before a public prototype that
  names an undeclared tag, as the book states.
- Buffer, Regex, and the Block encoders follow the null-handle rule
  (operation raises `<bad-arg>`; release forms accept null). Boxed Map
  `_bad_arg` keeps its `operation`. The bare `raise %(cause)` sites gain
  the `operation` detail the exceptions chapter promises.
- `x2c script` helper selection excludes the prelude's includes, not only
  the prelude sources.
- Retirement reads ignored paths with `-z`, as `gate-state.py` does, and
  its test gains a quoted-path case.
- `x2c test` prepares dependencies like `build` and `run`.
- The nested `packages/methodnames` fixture is registered the way the
  other package fixtures are (top-level link), and the runner's README
  says only top-level `.phases` run.

## Decisions approved by Gary (2026-11-02)

1. Admit the pinned libtorch Linux libgomp runtime under a narrow project
   exception. Retain the GPL, GCC Runtime Library Exception, and LLVM OpenMP
   license texts in the Torch bundle.
2. Keep archived plans and their historical evidence.
3. Remove the completed-records index; retain active and reference tables.
4. Keep the `typesafe-ai` skill.
5. Keep and test the listed public File, Lisp, and Var operations.
6. Remove redundant `sanity-check` builds while preserving bootstrap recovery
   and stages 0 through 3.
7. Require `orchestrate-x2c-work` whenever implementation subagents launch,
   including one delegated change.
8. Use one public command parser for each of `new` and package operations.
   Preserve direct invocation's literal response-file words. Package `ensure`
   remains a distinct internal dependency operation.

Gary also approved element provenance for the region analysis. The repair
preserves a container's actual allocation owner separately from its deferred
handle cleanup. Element access and helper summaries use that distinction.
It adds one pointer and one integer to `Fact`: 88 to 104 bytes on arm64.
It creates a transient Fact for an element read under the existing allocator;
compiled programs gain no state. The check remains conservative when an
explicitly region-born container holds only borrowed outer values.

## Batch A: bugs (parallel workers, disjoint files)

| Worker | Findings | Files |
| --- | --- | --- |
| identifiers | macro free name vs expansion-site alias (A1); alias-body lambda capture (A12); script alias of a renamed local (A19); `in` on a literal receiver (B6) | src/expressions/identifiers.x, src/macros/aliases.x, src/lambdas.x, src/compiler/parsing/scripts.x, src/expressions/operators.x (`in` only) |
| regions | outer-local assignment escape (A2); container read-back, views, write_str, MapSubInt rows (A3) | src/regions/** |
| string-runtime | detached-pool shortcuts (A4); unescape hex digits (A8); replace_fn null callback (A6) | lib/string/**, lib/regex.x, lib/scan.x (reader only) |
| protocol-transform | discard under truth and compound update (A5); conflicting-defaults diagnostic (A24) | src/transform/operators.x, src/protocol/** |
| generate | `struct tag;` forward declarations (A17); `#line` inside a continued string (A10) | src/generate/projection.x, src/format.x |
| lambdas | statement-expression reference capture (A11); `char[N]` capture (A15); `const` reference capture (A18) | src/components/lambda-functions.x |
| conversions | unresolved native call boxed to Var (A13); libc symbol to Func and lambda to a C callback (A14); calling a Var (A16); NULL literal to a by-value Func parameter (A20); String-or-NULL conditional (A9) | src/expressions/conversions.x, src/expressions/calls.x, src/expressions/operators.x (`_conditional` only), lib/http.x:545 |
| self-prototype | macro `Self` method prototype mismatch (A7); register the nested fixture | src/parse/declarators.x, src/parse/declarations.x, src/compiler/parsing/definitions.x, unittest/compiler-fixtures/packages/methodnames/**, unittest/compiler-fixtures/supervise.py, unittest/compiler-fixtures/README.md |
| null-handles | Buffer, Regex, Block encoder null handles (A21); boxed Map `operation`; bare raise sites (A22); Block null rule within the type (B3); detail keys `errno`, `offset`, size (B4) | lib/buffer.x, lib/block.x, lib/encoding.x, lib/map/**, lib/scope/regions.x, the other bare-raise owners, agents/x2c-code-standard.md (DG-7), docs/src/guide/exceptions.md, docs/src/library/time-random-encodings.md |
| driver-commands | lint-breaking line lib/regex.x:278 (A25, first, alone, so the gate is green); retirement `-z` (A26); script helper includes (A27); bind default dir (A28); help help (A29); test dependencies (A30); configure CC words (A31); REPL `#line` offset (A23); -v/-### flags (B13); script/test/package CLI differences (B12) | tools/integrate-dev.py, tools/test-integrate-dev.py, commands/build/build.x, commands/bind/**, src/cli/help.x, commands/test/main.x, configure, src/toolchain.x, commands/repl/repl-session.x, src/translation.x, src/cli/requests.x, docs/src/reference/cli.md |

Rules for every worker: reproduce from the probe in the review record,
repair the cause, prove it with a fixture or unit test that fails before
and passes after, run `make build` plus focused checks (and `make stage-1`
for emission changes), lint census on changed entry units, hand commits
to the orchestrator. Workers never merge `dev`, gate, or push.

## Batch B: partial landings, contracts, and waste (after batch A)

- Finish the batch B owners: `x2c_io_fail` at lib/channel.x:103,106,
  lib/digest.x:68, lib/random.x:120, commands/repl/repl-worker.x:397,402,
  418 and the private `_io_fail` in repl-input.x; `x2c_fatal` at
  lib/lisp/sessions.x:184, src/collect/cache.x:176,
  src/macros/rewrites.x:311; `Job.decode_wait_status` in repl-worker.x.
- Finish R27: one 0.15.0 date in release-notes.md and
  etc/release/README.md (UTC publication date, as 0.15.0 uses).
- Update examples/programs/literate-lisp.x:724 and STATUS.md for
  `Lisp.eval_file` reading through `File.string` (reference Lisp back to
  200/200), and the other stale STATUS entries (remainder sample, bm-all).
- Book and docs: `try` with a bare `catch:` (language.md, exceptions.md),
  `${k: v}` keys and bare keys (release-notes.md:29, scripting.md:621),
  participant `discard` (protocols.md:183, language.md:1172),
  retain/release wording (regions.md:192, storage-ownership.md:3), API
  tiers for Buffer, File.putw, Scope (docs/library-api-tiers.txt), the
  eight `x2c,ignore` samples that compile, Lisp assoc/member equality note
  (language.md:5117).
- Syntax-error message families: one message per condition for a missing
  `)` and for a keyword used as a macro name.
- VS Code grammar keywords and `using` in a macro header; CHANGELOG;
  one keyword table shared by lib/scan.x and etc/syntax/lexical.x, or a
  parity test.
- Tooling: tools/test-gate-state.py path; check.sh stderr on success and
  the three examples with conversion warnings; c2x2c in `list_sources`;
  dead categories; actions/checkout and node versions; release-validation
  claims vs torch; `PLATFORMS` as the single owner; THIRD_PARTY.md
  Linenoise; license hash claim in packages/AGENTS.md; pcre2 PROFILE
  pointer; performance-snapshot `--skip-if-success-today` keyed on the
  dev commit.
- Duplication clusters with a single owner available: record-the-cause
  try/catch macro in lib/test.x (67 sites); bounded `strtol` parsers to
  `String.try_long` (5); identifier-byte predicate (7); qualifier
  predicate and bitmask readers; leading-qualifier loop family (one
  `Type` owner, with the carried six); `_block_keywords` composition and
  the REPL copy; line/column loops to `scan_next_line_col`; LSP percent
  coding to lib/encoding.x; `_data_realloc`/`_raw_realloc`;
  `_unqualify_const`/`_without_const`; pointer Var tag map in
  type-ledger.x from var-tags.x; one filename hash for generated
  identifiers; platform string; SHA-256 helper in tools/; LSP test client
  and UTF-16 helper; `_cache_mix`; `MapStringInt.add_substr`;
  package `_<x>_live` guards (a shared macro in packages/).
- Waste removal: tools/check-release; packages/foreign-qualifier-deltas.json
  (or a reader); sourceview.o in the test link; dead fallback in
  run-compiler-translation.sh; `make N` header; duplicate make aliases
  and the commented recipe; check-doc-examples package flags; the 769
  default-only fixture sidecars; the 11 identical fixture sources as
  links; channel-service example pair; manifest stdout names.
- Guidance: archive plans/review-mitigation-2026-11-02.md and
  plans/detached-channel-ownership.md as done; move "Validate
  publication" and the integrator-only quick-start paragraphs into
  integrate-x2c-prs; one owner for the restated skill boilerplate (PR-4,
  diff review, Match pointer, proof list, graph caveat, bootstrap refresh);
  AGENTS.md repo map replaced by a link to src/README.md (and dropped from
  the check-docs module audit); TE-1/TE-3 text out of unittest/AGENTS.md;
  integrate-x2c-package restatement out; skills that say "follow root
  publication validation" say the integrator gates in PR mode.
- Apply the eight approved decisions above.

## Validation and delivery

Workers run focused checks and hand private commits to the orchestrator.
Gary selected direct delivery for this execution. The orchestrator owns the
combined review, generated artifacts, performance checkpoint, publication
gate, and explicit push to `dev`. The first authored commit rewraps the
Regex initializer. No `main` or release promotion is authorized.

## Execution record

The combined change repairs every selected Batch A finding. A second source
review found additional parenthesized-call, qualified character-array, and
const-destructuring paths; those repairs remain pending final worker evidence.

Scope corrections established while implementing:

- A8's quoted-collection subclaim is refuted by the book's nested String
  grammar and the tokenizer's deliberate percent-string token. Its behavior
  stays byte-oriented. Ordinary C text and runtime `String.unescape` consume
  C escape widths. No new C overflow policy was introduced.
- A19 retains the book's file-scope aliases. An alias that refers to a script
  local gets the existing script-local diagnostic, instead of invalid C.
  Aliases of static script variables remain valid.
- A21 preserves documented null observations such as Buffer length and
  Block truth. Mutations, required Regex operations, and Block encoders raise;
  release operations accept null. The book states these distinctions.
- String.printf allocates in Pool. A Scope-only `auto` does not end its
  result; the regression uses a nested Pool. Existing Scope behavior stays.
- The REPL repair corrects native diagnostic line numbers. Native compiler
  columns still describe the generated C; source-column reconstruction is
  not claimed.

The following Batch B deletion proposals were tested or traced and retained:

| Proposal | Evidence and disposition |
| --- | --- |
| Replace decimal parsers with String.try_long | `010` is decimal 10 at the command boundary but 8 through try_long; `08` is accepted only by decimal parsing; `0x10` and trailing whitespace are accepted only by try_long. Task uses unsigned capacities beyond LONG_MAX. Direct replacement changes syntax or range. Keep existing libc readers. |
| One packages-wide live guard | PCRE2 requires three native handles; SQLite statements depend on their database; BLIS views depend on their owner; Raylib checks native window state; libuv checks its loop and closing state. Causes and return contracts also differ. A shared include would add a bundle dependency without removing these predicates. Keep the existing owners. |
| One host-platform implementation | Native code uses uname and its diagnostic; shell installers must work standalone; Python dependency selection has its own platform API. No shared C/shell/Python owner exists without another process or bootstrap dependency. Retain local primitives. Release policy and verification matrices now use PLATFORMS. |

These decisions reject the proposed substitutions, not every future shared
implementation. They preserve the existing contracts without introducing a
new runtime API solely to wrap libc or a new package distribution dependency.

Completed focused evidence so far:

- All reported compiler regressions were reproduced before repair. Worker
  builds and strict stage-1 builds pass; their focused fixtures and unit
  suites are recorded in the workspace handoffs.
- The independent Lisp comparison passes 200/200 cases, with byte-for-byte
  exit, stdout, and stderr comparisons. File.string owns reading and NUL
  rejection; the interpreter owns apply's void-argument error and index.
- The integration tool's 61 offline tests pass, including quoted-path
  retirement. Configure's nine tests, six example-runner tests, 20 snapshot
  tests, and 14 release-helper tests pass.
- The VS Code Node and grammar checks pass. The common keyword tables gain
  parity coverage in the existing scanner suite.
- The 769 default-only fixture sidecars are removed without removing their
  runner failure conditions. Eleven identical flag variants share source
  files through relative symlinks. Thirty-five example output names follow
  their source names. One service example checks both schedulers.

Combined final validation and publication are pending. Host coverage remains
macOS arm64; no Linux or native Torch execution is claimed.
