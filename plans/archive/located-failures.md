> Status: done
> Published to `dev` on 2026-10-28: phase 1 in PR #603 (merge
> `a6edf5ac6`); phase 2 and the staging deferral repair in PR #604
> (`029c4494b`); the void-return check in PR #605 (`6e9f4fdbd`); and the
> expansion dump with the inspection repair in PR #607 (`26a85905b`). All
> seven decision 8 fixtures, `Var.convert_at`, and `--no-source-map` are on
> `dev`. The constructed array-dimension defect in `unittest/STATUS.md`
> predates this plan and stays outside it.
> Drafted 2026-10-28 against `gwf/repo-survey-major-features-933090`
> (`9aeeef265`) from reproduced probes. Implementation started 2026-10-28.
> The three
> public-behavior choices were settled with Gary on 2026-10-28 (see
> "Settled decisions").

# Located failures

Every failure a user sees names the user's source location, and a macro or
meta failure names its real cause and both sites: where the macro is
invoked and where it is defined or quoted. No language syntax changes.

## Evidence

All probes rerun on 2026-10-28 with `builds/0/x2c`. The probe sources are
kept under `plans/reference/probes-2026-10-28/located-failures/`; run each
with `builds/0/x2c run FILE` from the checkout root.

| Probe | Current text (before) | Cause in source |
| --- | --- | --- |
| `plans/reference/probes-2026-10-28/located-failures/m2_maptype.x:3` `int age = ages[<ada>];` | `x2c: uncaught <void-op>: operation Var.convert` | `lib/var/conversion.x` raises inside the runtime; `lib/logger.x` `_report_uncaught` omits a `(runtime 1)` location. The user's line is never recorded. |
| `plans/reference/probes-2026-10-28/located-failures/m2b_maptype.x:3` `int age = ages["ada"];` (value is a String) | `x2c: uncaught <no-convert>: target i32, cause (bad-types (source string))` | Same. |
| `plans/reference/probes-2026-10-28/located-failures/m5_oob.x:4` `int v = a[7];` | `x2c: uncaught <void-op>: operation Var.convert` | `Array.getindex` returns `void` by contract; the conversion fails without a site. |
| `plans/reference/probes-2026-10-28/located-failures/m3_cptr.x:5` | `/var/.../gen/m3_cptr-eb3960f9/m3_cptr.c:25:34: warning: result of comparison against a string literal ...` | `ToolRun.wait` (`src/toolchain.x:217`) relays cc's captured stderr verbatim; without `--source-map` the C has no `#line` directives. |
| `plans/reference/probes-2026-10-28/located-failures/f8-unit-type.x`, `plans/reference/probes-2026-10-28/located-failures/share.x`, `plans/reference/probes-2026-10-28/located-failures/p-unresolved.x`, `plans/reference/probes-2026-10-28/located-failures/p-voidreturn.x`, `plans/reference/probes-2026-10-28/located-failures/p-quote-unresolved.x` | `.../gen/<unit>.c:28:36: error: no member named 'nope'`, `fatal error: 'support/helpers.h' file not found`, `use of undeclared identifier 'zzz'`, `returning 'void' from a function with incompatible result type 'int'` | Same relay; member access, undeclared names, and void returns pass to cc untyped. |
| `plans/reference/probes-2026-10-28/located-failures/c2.x` (`$result[$member] = $value.$member`) | `c2.x:16:1: macro: this function cannot run at compile time` + `note: function: gen reason: a parameter or the result has no Var form, such as C's bool; ...` | Translating `gen` alone (`plans/reference/probes-2026-10-28/located-failures/c2-noinvoke.x`) reports the real cause: `c2.x:9:45: parse: expected identifier after '.'`, `note: token: $`. `src/macros/definitions/slots.x:40` gives a hole its kind at its first use; `$member` is an expression, so after `.` it is not a Name. The project meta build discards that parse diagnostic (`src/meta-project.x` `_parse_source` prints and records a failure only when `h.entries` is set), the group omits `gen`, the manifest records `(failures ())`, and the helper answers `(missing)`, which `src/meta-group/selection.x:131` explains with its last-resort guess. |
| `plans/reference/probes-2026-10-28/located-failures/b1.x`..`b3.x` (`result["k"]` in a quotation; `result` is declared in another quotation) | `b1.x:15:1: parse: type () does not support indexing` at the invocation | The free name `result` binds where the expansion lands (`src/expressions/identifiers.x` `_landed_name` -> `Sym.reference_global`), as `docs/src/guide/macros.md` "Keep a file-scope name with `using`" documents. The forward binding has no type, and `$fail.expressions_index_unsupported` prints the empty type. `c4.x` (`foo.set(...)`) already says `unresolved identifier: foo` because method receivers are checked (`src/expressions/calls.x:341`). |
| `plans/reference/probes-2026-10-28/located-failures/f1-type.x` | `f1-type.x:5:18: type: type (int) has no method len` | Correct location, no expansion context. `f4-recursive.x` shows the model note: `note: definition: FILE:2:1 input: (args ...)` from `src/macros/diagnostics.x` `$fail.macros_expansion_recursive` and `_definition_note`. |
| `run` of any file | three phase lines, `Built executable ... in 615 ms`, five muted receipts, `Running ...` | `commands/build/build.x` `$progress.*`; `src/report.x` receipts are on unless quiet, verbose, dry-run, or inspecting. |

Working programs (`derive.x`, `routes.x`, `stack.x`, `c2b.x`, `f3-hygiene.x`)
stay unchanged and are the regression set.

## Decisions

### 1. Runtime location for compiler-inserted conversions

Owner: `src/expressions/conversions.x` `_read_var`, `src/emit/dispatch.x`,
`lib/var/conversion.x`, `lib/error/dispatch.x`.

- `lib/error/dispatch.x` gains `void Error.raise_at(const X2CErrorSite *site,
  Symbol code, List detail)`: `_raise_enter`, `_record(site, ...)`,
  `_dispatch`. It is `Error.raise` with the site that `x2c_error_raise_n`
  already accepts; `_record` already takes a site. A NULL site records no
  location, as `Error.raise` does today.
- `lib/var/conversion.x` moves the body of `Var.convert` into
  `Var Var.convert_at(Var value, Symbol target, const X2CErrorSite *site)`;
  `Var.convert(value, target) => Var.convert_at(value, target, NULL)`. The
  `$error.convert.void`, `$error.source.numeric`, and `$error.no_convert`
  macros take `site` and call `Error.raise_at`. `<void-op>` detail gains
  `(target $target)`; existing detail pairs keep their names and order so
  `catch %(no-convert *cause)` in `unittest/test-varops.x:234` still matches.
  `Var.convert` keeps its signature (runtime ABI); the addition is
  compatible with the checked-in bootstrap, which keeps emitting
  `Var_convert`.
- `_read_var` emits `(call "Var_convert_at" (args $expr (expr ("Symbol")
  $tagsym) (error-site)))`. The emitter renders the new `(error-site)` node
  as `({ static const X2CErrorSite _x2c_gensym_error_site_N = { .file =
  "...", .function = "...", .line = L }; &_x2c_gensym_error_site_N; })`,
  the per-site static that `src/emit/expressions.x:200` already emits for
  `match_site`. The file, function, and line come from the same
  `e.origin_location(e.origin)` and `e.fn_name` reads as `_raise`; factor
  those lines into `_site_fields(e)` and use it from both. The site's
  `runtime` flag follows `_raise` (`e.c.runtime_inc`).
- Cost model: a static site costs one address per call and nothing on the
  value path; the failure path alone reads it. A const compound literal was
  measured instead (`diag/site-shape.c`): clang `-O0` stores it on the stack
  per call, so the static form is chosen. `diag/site-shape2.c` confirms the
  statement-expression shape compiles with `-std=c11 -O2 -Wall` and places
  the record in `__DATA,__const`.
- Message. The uncaught line already renders a located site
  (`docs/src/guide/exceptions.md`, `lib/logger.x` `_report_uncaught`):

  ```text
  x2c: uncaught <void-op> in main (m2_maptype.x:3): operation Var.convert, target i32
  x2c: uncaught <no-convert> in main (m2b_maptype.x:3): target i32, cause (bad-types (source string))
  x2c: uncaught <void-op> in main (m5_oob.x:4): operation Var.convert, target i32
  ```

  Key or index are not added: `Map.getindex` and `Array.getindex` return
  `void` by documented contract and nothing in the conversion sees the
  container. Fusing the read and the conversion into one call would be new
  machinery for a message detail; the source line the location names shows
  the bracket expression. Out-of-range `Array` writes (`a[7] = 9` is ignored,
  `plans/reference/probes-2026-10-28/located-failures/p-setindex.x`) are existing documented behavior and stay out of
  scope.
- Other compiler-inserted raises keep their runtime sites; `Var.convert` is
  the only one the newcomer probes reached. Extending `(error-site)` to a
  second runtime entry is a one-line change per entry when a probe shows it.

### 2. C compiler diagnostics

Owner: `commands/build/build.x`, `src/cli/parsing.x`,
`docs/src/reference/cli.md`.

- `build` and `run` translate with the source map on by default, so cc's
  own output names the `.x` file and line and shows the x2c source line
  under its caret. `src/format.x` already writes `#line L "FILE"` before
  each statement and a `#line N "GEN.c"` reset after it, so scaffolding
  keeps its generated location. No rewriting pass is added; the existing
  map does the work in cc.
- `translate` keeps its default (the bootstrap and `make` targets compare
  generated C byte for byte). `--source-map` stays accepted; `build` and
  `run` gain `--no-source-map` for the generated-C view. The build state key
  (`build.x:351`) already distinguishes `source-map` from
  `generated-lines`, so retained intermediates recompile when the flag
  changes.
- Intermediates: `Build.cleanup` already keeps the temporary work tree on
  failure (`build.x:1069`), and the `share.x` run shows the generated path
  in cc's text. Nothing changes for failure; on a successful build with cc
  warnings the tree is still removed, because the warning text now names
  the `.x` source.
- What the user sees:

  ```text
  m3_cptr.x:5:34: warning: result of comparison against a string literal is unspecified ...
    printf("eq literal: %d\n", raw == "hello");
  share.x:2:10: fatal error: 'support/helpers.h' file not found
  p-quote-unresolved.x:8:1: error: use of undeclared identifier 'zzz'
    $gen.it();
  ```

  The last line is the invocation site, because expansions use their
  invocation location in the map (`cli.md` "Source mapping"). The identifier
  and the invocation together name the macro; the `--dump-expansions` mode
  in decision 6 shows the expanded form.
- `cli.md` "Source mapping" and "Build and run" state the new default and
  that `__FILE__` and `__LINE__` in a `build` or `run` product name the `.x`
  source. This is the first decision for Gary below.

### 3. Meta staging failures

Owner: `src/meta-project.x` `_parse_source`, `src/meta-group/selection.x`,
`src/macros/definitions/slots.x`.

- `_parse_source` records the owner's first diagnostic for every build,
  not only a loaded one: when `unit.parse()` fails it writes
  `group-K.failure` with the line `_diagnostic_line` formats
  (`FILE:LINE:COL: CODE: MESSAGE; NOTE`), which `src/meta-group/emission.x`
  already builds for emission failures; make that formatter a module
  function and call it. `_compile` returns the text, `_record` stores
  `(K text)` in the manifest `failures` row, `_use` loads it, and the
  client's `_check` refuses the call with it. The manifest shape is
  unchanged; `(failures ())` simply stops being empty when a parse fails.
  Printing stays as it is: loaded builds print, ordinary builds carry the
  cause in the refusal note, so no diagnostic prints twice.
- `Compiler.meta_call_missing` keeps its two typed answers (aggregate and
  pointer results, which are facts the type establishes) and drops the "no
  Var form" guess as the default. The default becomes `its unit did not
  translate` followed by the recorded failure line when there is one;
  without one it says `the function is not in the unit's staged group`.
- The hole-kind cause gets its own report at the quotation, where the
  parser already knows both uses: `try_parse_macro_member` returns the slot
  when the hole's recorded kind is not `<name>`; instead it reports through
  a new `$fail.macros_hole_kind_conflict(c, token, name, kind)` in
  `src/macros/diagnostics.x`:

  ```text
  c2.x:9:45: parse: hole '$member' is an expression in this quotation and cannot name a member
    puts.push($!{ $result[$member] = $value.$member; });
                                            ^
    note: a quotation's first use of a hole gives it its kind; bind a second local for the member spelling
  c2.x:16:1: macro: this function cannot run at compile time
    $gen.it(Person);
    ^
    note: function: gen reason: its unit did not translate: c2.x:9:45: parse: hole '$member' is an expression in this quotation and cannot name a member
  ```

- The private-name cause is an expansion-time type error, not a staging
  failure. `$fail.expressions_index_unsupported` is reached with a receiver
  whose type is NULL and whose binding is a forward reference; in that case
  report `$fail.expressions_receiver_unresolved` (the message `c4.x`
  already gets) instead of printing the empty type. With decision 4:

  ```text
  b1.x:15:1: type: unresolved identifier: result
    $gen.it(Person);
    ^
    note: in expansion of 'gen.it' defined at b1.x:14:1; input: (Person)
  ```

  The note names both sites. The `using` paragraph of `macros.md` already
  explains why a free name binds at the landing site; the diagnostic does
  not repeat the book.

### 4. Expansion notes

Owner: `src/diagnostics.x` `Compiler.report_problem` and
`Compiler.report_warning`, `src/macros/diagnostics.x`.

- A diagnostic raised while `c.macro_stack` holds a frame with an
  invocation token appends one note built from the innermost such frame:
  `in expansion of 'NAME' defined at FILE:LINE:COL; input: REPR`, where the
  definition part is `_definition_note` and `input` is the frame's input
  with `(capture (source ...))` unwrapped as `_recursion` does, cut to 160
  characters with `...`. Frames without an invocation token are compiler
  lowerings (`_bind_expansion` comment) and add nothing.
- The expanded form is not in the note. The frame is pushed before
  `_construct` runs, because construction reads the active frame; storing
  the constructed form would need a second push or a side table. The
  expanded form belongs to decision 6.
- `_definition_note` and the unwrap move to module scope in
  `src/macros/diagnostics.x`; `_recursion` keeps using them.
- `f1-type.x` after:

  ```text
  f1-type.x:5:18: type: type (int) has no method len
      printf("%d\n", $half(n));
                     ^
    note: in expansion of 'half' defined at f1-type.x:2:1; input: (n)
  ```

### 5. Pre-C checks

Owner: `src/statements.x` `Compiler.finish_return_statement`,
`src/expressions/identifiers.x` (no change).

- Void return: `finish_return_statement` holds the resolved expression and
  `c.return_type`. When the expression's type is `void` and the return type
  is not, report `$fail.statements_return_void(c, token, return_type)`:
  `p-voidreturn.x:2:26: type: cannot return a void expression from a
  function returning int`. The later `convert_expression` has no rule for
  this pair, so nothing downstream repeats the check.
- Unresolved identifiers: binding does not know. `Sym.reference` and
  `Sym.reference_global` create a forward binding for any undeclared
  spelling, and `_using_names` records why: "A name no x2c declaration
  supplies is a native name left to C." The compiler has no inventory of C
  names from headers, so an x2c-level report on a bare operand would reject
  `printf` in a template as readily as `zzz`. The compiler reports only
  where it needs a type: method receivers today, bracket receivers with
  decision 3. Bare operands keep going to cc, which with decision 2 names
  the invocation line. This is the third decision for Gary.

### 6. Expansion dump

Owner: `src/translation.x` inspection switch, `src/cli/help.x`,
`src/macros/expansion.x` `_bind_expansion`, `docs/src/reference/cli.md`.

- `--dump-expansions` is an inspection mode like `--dump-ast`: it prints
  and stops after the parse. In `_bind_expansion`, after `bind_syntax`
  returns, an expansion with an invocation token prints under that mode:

  ```text
  expansion b1.x:15:1 gen.it
    definition b1.x:14:1
    input (Person)
    result
  (function ...)
  ```

  The result prints with `_node_repr` from `translation.x`, the same
  renderer as `--dump-ast`, so bindings read as the AST fixtures read.
  `c.code_pretty_string` was considered and rejected: it formats emitted C
  tokens, and the bound result is not transformed yet, so `c.emit` has no
  input it accepts. The pretty C of an expansion is what `--dump-code`
  prints for the whole unit.
- Nested expansions print in binding order, innermost first, each with its
  own header; the reader matches them by site.

### 7. Driver items

Owner: `commands/build/build.x`, `commands/build/main.x`, `README.md`,
`docs/src/reference/cli.md`.

- `$fail.build_input_unsupported` says `unsupported build input: first;
  program arguments follow '--'`.
- `README.md` "run" section adds `./x2c run hello.x -- first second` after
  the first run line, with one sentence that `--` starts the program's
  arguments.
- `run` without `-v` prints one line, `Built executable PATH in N ms`, and
  then the program's output; phases and receipts move behind `-v`.
  `report_configure` in `main.x` receives `quiet || (command == <run> &&
  !verbose)` for receipts, and `$progress.build_running` prints only under
  `-v`. `cli.md` "Build and run" says `-q` suppresses progress and
  receipts, which stays true; it gains one sentence for the default line
  and `-v`. `x2c run -q` in "Start a project" is unchanged. `build` keeps
  its current output. This is the second decision for Gary.

### 8. Validation

Compiler fixtures under `unittest/compiler-fixtures/` follow
`unittest/compiler-fixtures/README.md` (one `.phases` line per fixture):

| Fixture | Phases | Protects |
| --- | --- | --- |
| `located-convert-void` (m2 shape) | `stderr status` | the uncaught line names `main (FILE:LINE)` and `target i32` |
| `located-convert-string` (m2b shape) | `stderr status` | `<no-convert>` keeps its detail pairs and gains the site |
| `quotation-hole-kind` (c2 shape) | `compile-status diagnostics` | the hole-kind report at the quotation and the refusal note that carries it |
| `quotation-free-name-index` (b1 shape) | `compile-status diagnostics` | `unresolved identifier` with the expansion note |
| `expansion-note-method` (f1 shape) | `compile-status diagnostics` | the note on an ordinary type error inside an expansion |
| `return-void-typed` | `compile-status diagnostics` | the void-return report |
| `dump-expansions` | `expansions` | the dump's shape; the fixture runner maps the new phase to `--dump-expansions` as it maps `ast` |

Runtime tests: `unittest/test-varops.x` gains one case that calls
`Var.convert_at` with a site, catches `<void-op>`, and checks the
`location` field names that function and line; the existing
`catch %(no-convert *cause)` cases prove detail compatibility.

Driver and cc relay: `commands/build/tests` gains one build of a unit with
a deliberate cc warning asserting the `.x` path in the relayed text, and one
`run` asserting the single default line. The newcomer and macro probes
above are rerun after each phase and their after-text recorded in this
file's evidence table.

## Phases

1. Runtime locations, cc relay, driver items (decisions 1, 2, 7). About
   60 lines in `lib/`, 40 in `src/`, 30 in `commands/build`, 20 of docs,
   four fixtures. Full gate: runtime and emitter change.
2. Meta and macro diagnostics (decisions 3, 4). About 60 lines in `src/`,
   three fixtures. Full gate.
3. Expansion dump and the void-return check (decisions 5, 6). About 50
   lines in `src/`, two fixtures, `cli.md`. Full gate.

Each phase is a separate delivery; phase 2 does not depend on phase 1.

## Settled decisions

Gary agreed on 2026-10-28:

1. `build` and `run` enable the source map by default. `__FILE__` and
   `__LINE__` in those products name the `.x` source, and debuggers step
   `.x` lines with `-g`. `--no-source-map` and `translate` keep generated-C
   locations. The sidecar line map was rejected as a second owner of the
   mapping.
2. `run` prints one line by default; the phase lines and receipts stay
   behind `-v`, as `script` already does.
3. No x2c-level report for a bare undeclared identifier. Forward-binding
   unknown spellings as C names is the premise that lets x2c call any C
   function without declarations. The expansion note and the unresolved
   receiver report cover the macro case that was reproduced. An opt-in
   `--strict-names` is not planned.

## Plan review

- Facts established upstream and not rechecked: `_record` already stores a
  caller's site; the emitter already computes file, function, and line for
  `raise` and already emits per-site statics for `match_site`; `format.x`
  already writes the `#line` map; the hole record already holds the kind
  from the first use; `c.macro_stack` already holds definition, input, and
  invocation for every active expansion; `Build.cleanup` already keeps the
  tree on failure. No consumer rechecks them.
- Reuse and deletion: `Error.raise_at` replaces nothing but is the only
  new runtime entry; `Var.convert` becomes a one-line forwarder;
  `_site_fields` is shared by `_raise` and `(error-site)`;
  `_diagnostic_line`, `_definition_note`, and the input unwrap become
  shared module functions instead of copies; the "no Var form" guess is
  deleted; `expressions_index_unsupported` reuses the existing unresolved
  report. New lasting mechanisms: the `(error-site)` node, one note builder
  in `diagnostics.x`, one inspection mode, and the hole-kind and
  void-return reports. Each prints a fact the compiler already holds and
  did not say.
- Idiom: the sites are static C records the emitter writes, as `raise`
  does; the runtime change is a parameter, not a thread-local or a
  registry; diagnostics stay in owner catalogues as
  `agents/logger-and-diagnostics-guide.md` prescribes.
- Validators and negative fixtures: the seven fixtures and the two command
  tests above each protect a message a user otherwise reads wrong: a
  location-free abort, a generated-file path, a guessed meta cause, an
  empty type, a missing site, a cc error for a fact the compiler holds.
  There is no validator that repeats a known fact.

## Last step

Before publication validation, review the completed authored diff for each
phase against this review: a second site computation, a note built where a
shared builder exists, a check that repeats a type fact, or a message that
does not name the user's location. Fix what the review finds, rerun the
probes in the evidence table, record the after-text here, then run
`tools/gate-state.py ensure agent-pr-check`.


## Execution evidence (2026-10-28)

This execution uses shared-integrator delivery. Focused checks run in the
implementing worktrees and the submitting worktree. The integrator owns final
bootstrap and documentation regeneration, performance evidence, the full gate,
and publication. The phase descriptions above do not require worker gates.

### Phase 1: runtime sites and driver

Implemented the compatible `Error.raise_at` and `Var.convert_at` entries,
static conversion sites, default build/run source maps, `--no-source-map`,
program-argument guidance, and the single default run receipt. Explicit
extractors retain their existing runtime error locations. Quiet output still
wins over verbose progress.

Source includes previously discarded their origin before emission. The
source-aware directive reader now preserves the existing `at` wrapper for
includes, and projection/dependency readers inspect through that wrapper.
Raw directive analysis and unmapped translation keep their existing shapes.
Meta group include replacement and leading-directive ordering also inspect
through the wrapper. Independent review reproduced and repaired a missed
meta-provider include consumer; its multiunit driver regression now passes.

Observed after-text (paths below are under the retained probe directory):

| Probe | Observed result |
| --- | --- |
| `m2_maptype.x:3` | `<void-op> in main (FILE:3): operation Var.convert, target i32` |
| `m2b_maptype.x:3` | `<no-convert> in main (FILE:3): target i32, cause (bad-types (source string))` |
| `m5_oob.x:4` | `<void-op> in main (FILE:4): operation Var.convert, target i32` |
| `m3_cptr.x:5` | Native warning names the `.x` file and line. |
| `share.x:2:10` | Native missing-header error names the source include. |
| `p-quote-unresolved.x:8` | Native undeclared-name error names the invocation line. |
| `p-setindex.x` | Existing ignored out-of-range write still succeeds. |

Correction to decision 2's example: `#line` changes the native diagnostic's
filename and line. Clang can still show generated C beneath its caret,
including a generated column number for an expanded expression. No diagnostic
rewriter or source-map sidecar was added.

Focused worker checks passed: build-safe/build, the external build command
probes, 18 varops tests with 7,279 assertions, both new conversion fixtures,
35 affected existing conversion fixtures, three include fixtures, and the
source-map retained-build reuse probe. Updated fixture artifacts contain the
reviewed conversion call/static-site changes. Final generated publication
artifacts remain with the integrator.


### Phase 2: meta causes and expansion notes

Implemented the quotation member-hole diagnostic, unresolved bracket receiver
report, staged failure propagation, and innermost expansion notes. The shared
meta diagnostic formatter and input unwrap now have one reusable owner.

The staging premise needed correction. Ordinary staging deliberately defers
slot invocations whose generated declarations are not available yet. The
first error diagnostic now distinguishes that `meta-later` deferral from a
real parse failure. Errors after a deliberate deferral remain translation's
responsibility. Warnings do not become refusal causes. Loaded builds keep
printing their failures. No staging state or manifest format was added.

| Probe | Observed result |
| --- | --- |
| `c2.x:16:1` | Refusal carries the real quotation failure at `c2.x:9:45`, including the expression/member hole conflict. |
| `c2-noinvoke.x:9:45` | Reports the hole conflict directly at the quotation. |
| `b1.x:15:1` | `type: unresolved identifier: result`, with `gen.it` definition and input note. |
| `f1-type.x:5:18` | Existing method error now includes the `half` definition and input note. |

Focused worker checks passed: 547 diagnostic fixtures, then eight checks
covering the warning correction and related meta behavior. The rollback
fixture's valid meta provider moved to a support unit so the erroneous
consumer still tests both original rollback/placement failures. Removing new
expansion notes from existing sidecars recovers the previous diagnostic bytes
except the planned unresolved-index and missing-group messages and that
fixture relocation.

The working examples `magic/meta-functions`, `magic/imported-macros`, and
`magic/stacked-decorators` exit zero and match their manifest output. The plan's
`derive.x`, `routes.x`, `stack.x`, `c2b.x`, and `f3-hygiene.x` were unavailable;
they were not run. The three checked-in examples cover working meta functions,
imported macros, and stacked decorators instead.

The expansion notes work independently of the proposed dump metadata.
Existing retained function and initializer rows already restore their
construction stack; bounded Unit probes report both invocation and definition
without adding metadata. The separate dump extension was measured and approved for adoption, as
recorded below.


### Phase 3: return check and adopted expansion dump

Implemented the void-expression return diagnostic using resolved source and
return types, including typedef aliases to void. Ordinary and expression-body
parsers retain the expression's token so the error points at the expression.
The retained `p-voidreturn.x` probe reports line 2, column 26 before native
compilation. Decision 5 was submitted separately in PR #605.

Gary approved adoption and shared-integrator submission of the measured dump
on 2026-10-28. `--dump-expansions` prints invocation/definition locations,
input, and bound results, then stops after parsing. The shared AST renderer
keeps binding numbers stable. Input unwrapping reuses phase 2's owner.

Retained Unit productions carry nested `exp-begin`/`exp-end` rows only in dump
mode. Default selection preserves these boundaries. Replay prints bound result
ranges without executing producers again. Ordinary builds keep existing
production records and allocate no inspection markers, frames, or ranges.
Compiler objects are 944 bytes with both the planned dump flag and metadata,
compared with 936 bytes before the dump feature. Metadata adds flag checks,
child flag copying, and a restoration wrapper call on ordinary paths.

The measured correction uses a Match dispatcher for inspection rows. An
earlier pattern-if chain failed a strict native build with a dangling-else
warning; those failed-build observations are excluded from the comparison.
The unused stream experiment was reverted and is not included.

### Metadata measurements and scope

The comparison isolates metadata against the planned dump checkpoint, not the
whole feature against the delivered compiler. Both compilers were converged
with matched preludes. Gary explicitly authorized measurement under sustained
background load. Five alternating six-input translation pairs and three
alternating clean stage-1 build pairs completed. Each stage build translated
72 runtime, 62 compiler, and five driver units with 139 native compilations.
All six clean builds passed without warnings.

| Median metric | Planned dump | Metadata prototype |
| --- | ---: | ---: |
| Direct translator instructions | 27,224,285,087 | 27,196,788,005 |
| Clean stage-1 elapsed seconds | 11.061 | 11.440 |
| Clean stage-1 child-inclusive CPU seconds | 40.366 | 42.077 |

Instruction ranges overlap. Paired elapsed differences were -1.447, -0.132,
and +0.379 seconds. Loaded timings do not establish a consistent slowdown or
speedup. Make's retired-instruction counter excludes descendants and is not
reported as a whole-build instruction metric. Twelve fixed-input C/H files
matched exactly, totaling 1,724,218 bytes. Publication performance evidence
and the full gate remain the integrator's responsibility.

Focused prototype coverage includes nested expression and Unit macros,
typedef-only and empty Units, included definitions, generated defaults, and
expression arguments supplied to Units. The independent constructed
array-dimension defect is recorded in `unittest/STATUS.md`; it also fails in
the baseline compiler and was not repaired by this plan. Its initially
suspected connection to lost inspection metadata was disproved.

Runtime/driver, macro diagnostics, and return checks were submitted as PRs
#603, #604, and #605. The expansion dump completes the authored plan; final
bootstrap/doc regeneration, full publication validation, and dev publication
belong to the integrator. Submission does not establish publication.


### Integration repair (2026-10-28)

The repair chain is replayed on fixed integration base `dea671913`, without
merging a moving dev branch. Staging now defers a pattern-producing call
outside a meta body instead of replacing its result with integer zero.
Ordinary meta-body calls and genuine staged failure causes retain their
existing behavior.

Expansion-note presentation replaces binding identities with source spellings
and cache identities with per-input ordinals before rendering and truncation.
Repeated cache references keep the same ordinal; distinct caches keep distinct
ordinals. Literal payloads remain opaque. Semantic source unwrapping belongs
to AST and is unchanged. Diagnostics owns note formatting, avoiding a macro
object dependency in the isolated unit runner. All callers, including completed
quotations and expansion dumps, use those owners.

The existing protocol probe now covers binding, literal, and quotation inputs
with the same snapshot/live compiler invocation count and exact full stderr
comparison. Both `source_capture` and `dump_expansions` remain shared by child
compilers. Repair submission requires focused checks and `make stage-2` on the
committed combined candidate; the integrator still owns the final full gate,
generated artifacts, and dev publication.
