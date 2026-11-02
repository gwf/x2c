# Deep review remediation (2026-11-02, second pass)

> Status: active - plan written; no batch has started. Review baseline
> `dev` 6f537e429 (PR #648 merged). The review record is workspace-local
> (`.context/review-2026-11-02/REPORT.md` with ten per-area files in
> worktree `interesting-northcutt-0886af`); this plan carries the
> decisions and the batch map. Delivery follows the root `AGENTS.md`
> default (ready PRs to the shared integrator) unless Gary selects
> otherwise.

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
- `String.unescape` and the quoted-literal reader use the C escape rules
  that `scan_c_escape_value` implements; the x2c rule stays for `%()`.
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

## Decisions for Gary

1. Torch bundles ship `libgomp` (Linux) and `libomp` (macOS) with no
   license text; `packages/LICENSE-POLICY.md` rejects GPL by default.
   Record an exception for libgomp (GPL-3 with the GCC runtime exception)
   and add both license texts, or drop libgomp from the Linux bundle.
2. `plans/archive`: 38 plans (6,107 lines) with no inbound reference and
   38 more (8,083 lines) referenced only from inside the archive. The
   README forbids deletion. Keep, or amend the rule and delete.
3. `plans/README.md` completed-records index (398 lines, 115 rows that
   repeat archive status headers): cut to the active and reference
   tables, or keep.
4. `typesafe-ai` skill (170 lines plus LICENSE, unrelated to x2c): keep or
   remove.
5. Public runtime surface with zero callers and no tests: `File.putw`,
   `getw`, `setlinebuf`, `setbuffer`, `scanf`, `Lisp.remove_global`,
   `Var.fallback_compare`, `Var.fallback_hash`. Remove, or keep and test.
6. `sanity-check` compiles the bootstrap twice and stage 0 three times
   (about 7 s); changing it is under the process ceiling.
7. Root `AGENTS.md:49` says a session that launches implementation
   subagents loads `orchestrate-x2c-work`; the skill says not for a single
   change. Which rule stands for one delegated change.
8. Legacy second argument parsers in `x2c-new` and `x2c-package` (two
   help texts, two error texts each): remove or keep.

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
- Items 1 to 8 above as Gary decides them.

## Validation and delivery

Workers: focused checks only. Orchestrator: combined focused checks,
`make stage-1` on the integrated batch, lint census on changed entry
units, `git diff --check`, then `tools/integrate-dev.py submit` with the
focused evidence. The integrator owns the publication gate and `dev`.
Batch A's first commit is the lib/regex.x rewrap so the census is green
before anything else lands.
