# x2c Beautification Project

> Status: active. Wave 0, the pilot, and Waves 2 and 3 are on `dev`. Waves
> 4 and 5, the compiler front end, core, and semantics, are next; their
> files are shared with the dual-macro migration, so each batch starts with
> agreed file boundaries. The baseline measurements are from `dev`
> `f6606dbf`. Track H waits for Gary's approval of its book text.

## Progress

Wave 0, delivered 2026-09-28:

- The style guide has the "Shape" chapter, the reading-order section, the
  naming glossary, and shape questions in its review checklist.
- `beautify-x2c-source` holds the procedure, with a coverage-probe
  reference. `x2c lint` reports `long-function`, `deep-nesting`,
  `long-parameter-list`, and `long-name` candidates.
- The coverage probe ran once over the whole workload: 87.6% of 29,644
  executable `.x` lines ran, and 485 of 4,160 functions never ran. Most of
  those serve `x2c build`, project manifests, and the editor adapter,
  which the workload does not run. Three have no callers:
  `Compiler.shared_definition` (`src/macros.x`),
  `Compiler.region_no_lifetime_effect` (`src/regions.x`), and
  `Macro_case_capture` (`lib/meta.x`). Their waves delete them.

Pilot results:

| File | Lines | Functions | Mean length | Longest | Over 40 | Most parameters |
| --- | --- | --- | --- | --- | --- | --- |
| src/collect.x before | 1,104 | 55 | 15.5 | 130 | 2 | 12 |
| src/collect.x after | 1,189 | 94 | 8.7 | 22 | 0 | 6 |
| lib/tokenizer.x before | 843 | 48 | 13.3 | 157 | 3 | 7 |
| lib/tokenizer.x after | 968 | 75 | 9.1 | 57 (a mode table) | 1 | 4 |

Both files grew, mainly from the new records' definitions, helper
signatures, and section labels. Stage 1 translated `src/` and `lib/`
byte-identically to stage 0 after each file. Five alternating timing pairs
of six compiler sources measured the candidate 1.7% faster with interfaces
and 0.4% faster without them, both inside the run-to-run noise.

The rewrite exposed a latent defect. `collect_forget_entries_since`
deleted cache entries while iterating the same Map, so it skipped entries
depending on allocation addresses; `meta-import-included` then failed from
a cold cache. It is fixed on its own commit. `.xi` interfaces still write
selected definition rows that no reader has used since `30615669`; the
loader no longer passes them along, and the format is unchanged.

Wave 2, delivered 2026-09-28: the driver files. Each file's columns show
the measure before and after, as `before / after`.

| File | Lines | Functions | Longest | Over 40 | Most parameters |
| --- | --- | --- | --- | --- | --- |
| src/build.x | 1,179 / 1,270 | 52 / 92 | 104 / 25 | 4 / 0 | 4 / 4 |
| src/cli.x | 1,209 / 1,237 | 41 / 66 | 80 / 35 | 5 / 0 | 9 / 3 |
| src/main.x | 627 / 700 | 21 / 47 | 73 / 28 | 5 / 0 | 5 / 4 |
| src/project.x | 815 / 900 | 41 / 73 | 100 / 20 | 3 / 0 | 7 / 5 |
| src/frontend.x | 420 / 472 | 18 / 31 | 68 / 26 | 3 / 0 | 5 / 5 |
| src/meta-project.x | 483 / 607 | 17 / 40 | 89 / 21 | 3 / 0 | 10 / 4 |
| src/install.x | 424 / 479 | 29 / 38 | 44 / 21 | 1 / 0 | 8 / 4 |
| src/toolchain.x | 428 / 464 | 25 / 36 | 37 / 19 | 0 / 0 | 7 / 7 |
| src/utils.x | 417 / 434 | 36 / 37 | 19 / 13 | 0 / 0 | 4 / 4 |
| src/report.x | 245 / 281 | 16 / 24 | 30 / 12 | 0 / 0 | 6 / 6 |
| src/editor.x | 212 / 256 | 8 / 17 | 52 / 19 | 2 / 0 | 6 / 4 |
| src/script.x | 113 / 148 | 5 / 11 | 33 / 25 | 0 / 0 | 1 / 2 |
| src/deps.x | 139 / 137 | 4 / 7 | 34 / 20 | 0 / 0 | 4 / 4 |
| src/sourceview.x | 76 / 74 | 5 / 5 | 18 / 17 | 0 / 0 | 4 / 4 |
| src/meta-helper-client.x | 263 / 324 | 11 / 21 | 55 / 24 | 1 / 0 | 4 / 4 |
| src/generate.x | 1,288 / 1,390 | 66 / 105 | 92 / 28 | 3 / 0 | 6 / 5 |

Together the sixteen files went from 8,338 to 9,173 lines: 6,482 `.x`
lines added and 5,647 deleted. No function over 40 lines remains, down from
30. The files grew for the pilot's reasons: record definitions, helper
signatures, and section labels. After the whole batch, stage 1 translated
`src/` and `lib/` byte-identically to stage 0. Five alternating timing pairs
of six compiler sources gave a median candidate-to-base ratio of 0.99 with
interfaces and 1.01 without them, inside the run-to-run noise of a loaded
host.

The workers kept every public name and signature. Integration then gave
two repeated jobs one owner each. `toolchain_new` takes the `CliRequest`
whose seven fields three callers copied out, and `toolchain_meta` serves
the two callers that pass only a meta compiler. `report_generated` prints
the "Generated N C files and N headers" receipt that `main.x` and
`build.x` both spelled out.

The workers found these defects, which predate the wave. Each reproduces
on the original code and has its own fix task, so the wave keeps the
behavior. Two fixes are merged into this batch, and the others land
separately:

- `x2c build -###` recorded the final archive fingerprint, so a later
  build kept an archive built from older objects. Fixed by `a4fdb9f0`.
- A manifest field with an empty value, such as `output =`, crashed
  `x2c build`, and a second `[dependencies]` section was accepted when the
  first one was empty. Fixed by `99d6e8f3`.
- `in` after an interpolated String literal does not parse.
- `x2c help ''` crashes, and `x2c @` reports `response file '(null)'`
  where it means `empty response-file reference '@'`.
- When `fork` fails, a meta call reports "the body exited with status 0"
  instead of "the compile-time helper did not start", and two pipe ends
  leak.
- A unit's own `meta` function with a struct result, called as
  `$twin(1).a`, reports a C compiler error from the generated group
  instead of the struct-result reason.
- `#pragma private /* not pragma public */` publishes the declarations
  after it in the header. `generate.x` tests `pragma public` first, while
  `collect.x` and `compiler.x` test `pragma private` first; the three copies
  of that test need one owner.
- Generated C embedded checkout paths through macro definition files. This
  one is fixed on `dev` as `4d251b35`.

Candidates left for later waves:

- `Toolchain.preprocess` takes its receiver, three inputs, and three
  out-parameters. A result record would bring it to four parameters.
- `_shell_status` in `src/utils.x` repeats `_decoded_status` in
  `lib/process.x`, and `_valid_utf8` in `src/cli.x` accepts the same input
  as `_utf8_length` in `lib/json.x`. Each needs a new public runtime
  owner; Wave 3 left both in place.
- `src/utils.x` holds several subjects: environment discovery, source
  files and packages, compiler identity, file locks, translation workers,
  and the driver's error line.

Wave 3, delivered 2026-09-29: 27 runtime files. Each file's columns show
the measure before and after, as `before / after`.

| File | Lines | Functions | Longest | Over 40 | Most parameters |
| --- | --- | --- | --- | --- | --- |
| lib/string.x | 1,773 / 1,841 | 88 / 120 | 119 / 28 | 3 / 0 | 5 / 4 |
| lib/var.x | 1,281 / 1,272 | 73 / 88 | 54 / 28 | 1 / 0 | 3 / 3 |
| lib/varops.x | 601 / 583 | 28 / 41 | 45 / 30 | 2 / 0 | 5 / 4 |
| lib/varconvert.x | 298 / 289 | 15 / 16 | 34 / 27 | 0 / 0 | 4 / 4 |
| lib/match-machine.x | 571 / 526 | 23 / 46 | 270 / 54 | 1 / 1 | 5 / 5 |
| lib/machine.x | 484 / 480 | 16 / 17 | 25 / 25 | 0 / 0 | 7 / 7 |
| lib/pool.x | 965 / 1,000 | 57 / 72 | 46 / 24 | 1 / 0 | 4 / 4 |
| lib/buffer.x | 359 / 357 | 27 / 32 | 46 / 17 | 1 / 0 | 3 / 3 |
| lib/block.x | 322 / 331 | 22 / 30 | 43 / 17 | 1 / 0 | 3 / 3 |
| lib/list.x | 1,036 / 1,037 | 81 / 91 | 44 / 18 | 1 / 0 | 4 / 4 |
| lib/error.x | 1,327 / 1,401 | 79 / 97 | 58 / 23 | 3 / 0 | 4 / 4 |
| lib/scan.x | 749 / 693 | 44 / 56 | 71 / 71 | 2 / 1 | 4 / 4 |
| lib/process.x | 578 / 618 | 39 / 51 | 58 / 20 | 1 / 0 | 6 / 4 |
| lib/thread.x | 309 / 338 | 13 / 17 | 43 / 24 | 2 / 0 | 3 / 3 |
| lib/path.x | 544 / 559 | 41 / 45 | 45 / 32 | 1 / 0 | 4 / 4 |
| lib/regex.x | 746 / 813 | 56 / 75 | 57 / 21 | 2 / 0 | 6 / 6 |
| lib/diff.x | 171 / 243 | 8 / 19 | 55 / 19 | 1 / 0 | 6 / 5 |
| lib/datum.x | 229 / 264 | 10 / 16 | 56 / 21 | 1 / 0 | 3 / 3 |
| lib/dispatch.x | 920 / 942 | 64 / 72 | 30 / 25 | 0 / 0 | 6 / 6 |
| lib/func.x | 443 / 426 | 25 / 25 | 32 / 28 | 0 / 0 | 5 / 5 |
| lib/scope.x | 1,033 / 1,073 | 58 / 66 | 30 / 21 | 0 / 0 | 4 / 4 |
| lib/iter.x | 879 / 890 | 54 / 54 | 18 / 18 | 0 / 0 | 4 / 4 |
| lib/file.x | 591 / 596 | 46 / 48 | 38 / 24 | 0 / 0 | 4 / 4 |
| lib/logger.x | 847 / 860 | 48 / 58 | 35 / 20 | 0 / 0 | 5 / 5 |
| lib/lisp.x | 2,072 / 2,160 | 159 / 191 | 104 / 23 | 2 / 0 | 7 / 5 |
| lib/meta.x | 872 / 980 | 48 / 64 | 35 / 21 | 0 / 0 | 5 / 5 |
| lib/match.x | 2,686 / 2,776 | 159 / 192 | 82 / 30 | 7 / 0 | 7 / 6 |

Together the 27 files went from 22,686 to 23,348 lines: 13,767 `.x`
lines added and 13,105 deleted. Functions over 40 lines fell from 33 to 2:
`_execute`, the match machine's dispatcher of one- to three-line arms, and
`scan_keyword_type`, whose compare chain stays because a table cost a load
per lookup. After the whole batch, stage 1 translated `src/` and `lib/`
byte-identically to stage 0. The other runtime files were already inside
the bands; they get a review-card pass later.

The checkpoint ran each benchmark in both trees through paths of equal
length, because a path one character longer moves the first heap cells and
shifts small benchmarks. The first run found real instruction costs in
`lib/scan.x` (number and string-segment scanning, keyword tables) and
`lib/var.x` (integer reads and float boxing, where one helper made clang
compute every arm). Both workers restored the base code shape at those
spots and marked each with a comment. After the fixes, the whole benchmark
binaries retire 0.5% fewer instructions for scan and stay within 0.2% of
base for Var and String. Translating six compiler sources took the same
median wall time over seven cold pairs, with 0.6% fewer instructions, and
2% fewer instructions with interfaces. Single tight loops still move by
about 10% in wall time with code layout; their instruction counts show no
extra work.

Coordination: the dual-macro migration released `lib/lisp.x`,
`lib/meta.x`, and `lib/match.x` for this batch and kept `src/transform.x`.
The two sessions exchange exact file boundaries before either starts
another shared file.

Behavior-adjacent changes, each listed in its commit message:

- `Macro_case_capture` is deleted: it had no caller, and the compiler
  emits `Macro_case_capture_at`.
- Lisp evaluation frames are smaller, so non-tail recursion reaches the
  unchanged byte limit about 17% deeper before `<call-stack>`.
- A raise moved into a static helper records that helper as its location.
  The locations that fixtures and the varops probe pin are unchanged.
- `_record_n` in `lib/error.x` reads a key and its value in two statements;
  one struct initializer left their order unspecified.

The workers found these defects, which predate the wave. Each reproduces
on the original code, and each has its own fix task that waits for this
batch:

- `String.parse_char` on a lone `'` reads the byte after the NUL, and
  `String.len` on a fresh `String.malloc` buffer contradicts its
  documentation.
- `x2c lint` offers `.` for every `->`, which breaks `struct dirent` on
  macOS, where x2c cannot see the layout.
- The fixture supervisor can crash with `PermissionError` from
  `os.killpg` after a timeout.
- `make bm-match-cache` does not build: its runner never translates
  `unittest/match-recursive.x`.
- `MatchPlan.prepare` raised `<bad-arg>` instead of reporting
  `code-capacity` when an `!or` arm ended at the 4,096-word limit; `!not`,
  guard binders, and search stars failed the same way. Fixed by
  `1edf04d3`.
- `Var.new` with a built-in aligned pointer tag and a misaligned pointer
  builds a box whose `.tag()` crashes.
- Regex repetition counts past `INT_MAX` wrap: `a{2147483648}` acts like
  `a*`.
- Lisp `apply` with more than eight values leaks its argument array, 144
  bytes per call.

Candidates left for later:

- `MachineBuilder.view` has no callers, and `MachineBuilder.emit` takes 7
  positional parameters at 109 call sites; both are public, so Gary decides.
- `MatchMachine.open` and `dispose` belong in `lib/match-machine.x`, but
  `lib/match.x` calls them and `match-machine.x` includes `match.x`.
- `lib/string.x` stays over 1,500 lines; its formatting code (about 350
  lines) uses nothing private and could be its own unit, like
  `string-number.x`. `lib/meta.x` holds the meta surface and about 600
  lines of macro-value machinery, which could also be its own unit.
- Repeated jobs that need a new public owner: the one-argument `FuncArg`
  stanza (nine times across list, iter, array, and string), `_hex_digit`
  (json and string), the invalid-bits raise (varconvert and dispatch),
  `_shell_status` (`src/utils.x`) against `_decoded_status`
  (`lib/process.x`), and `_valid_utf8` (`src/cli.x`) against `_utf8_length`
  (`lib/json.x`).
- `x2c lint` suggests `LispEnv &local` for `_bind_values`, which the
  compiler's region check then rejects.

## Context

Gary asked for a campaign that makes x2c's own source beautiful. The
compiler and runtime are the code agents copy, so ugly files produce more
ugly code. The rewrite may split, merge, rename, reorder, and regroup any
function or file. Behavior stays identical. Algorithms and data structures
stay the same, except small tweaks that are neutral or better and make the
code easier to read. Gary named four targets: shorter functions, more code
reuse, names that are neither cryptic nor verbose, and files organized for
a reader. Work starts at the level of the file: its order, its sections,
and the functions inside it. The plan also answers Gary's question about a
built-in source hierarchy (Track H).

The gap is measurable. `src/` has three times `lib/`'s share of lines in
long functions, names 60% longer, and nine times as many functions with
seven or more parameters. The monoliths also hide dead code: this review
found an unreachable `case`, uncalled methods, and returns after calls that
never return, all inside live files.

## The house standard

### Principle

A reader has a limited budget on each axis: function height, line width,
name length, nesting depth, and parameter count. Beautiful code keeps every
axis inside a middle band and keeps adjacent elements at similar sizes, so
no element is much larger or smaller than the ones around it. Routine work
is compressed: guards on one line, tables, `=>` bodies, system macros. The
algorithm is expanded: one named step per idea. Each job has one owner, and
every caller reuses it. Work that is not the point of a function or file
gets one named place. A file reads top to bottom as an explanation of one
subject. The same rules apply at every level: line, function, section,
file, and directory (Track H).

### Bands

| Axis | Too little | Band | Too much |
| --- | --- | --- | --- |
| Line | a call split although it fits | one idea, up to 79 columns | two ideas; nested ternaries |
| Name | an abbreviation outside the glossary | subject letter; 1-2 word locals; 2-3 word helpers | 25+ characters; the file's subject repeated |
| Function | a one-use wrapper that owns nothing | 3-25 lines | over 40 lines, unless a table or a dispatcher with one-line arms |
| Depth (body = 1) | - | 3 or less | 5 or more |
| Parameters | - | 4 or fewer | 7 or more |
| Section | a label over one function | 3-12 functions | over 400 lines, or two concepts |
| File | a file for one helper | one subject, 200-1,200 lines | several owners; over 1,500 lines |

### Rules

Functions

1. One job at one level of abstraction. The body reads as named steps. If
   the one-sentence purpose needs "and", split the function.
2. A dispatcher only dispatches. Each `match` or `switch` arm is one line
   that calls a named helper. An arm longer than three lines moves out.
3. Guards come first and the main path follows. Early returns replace flag
   variables and `else` ladders.
4. No mode flags. A parameter or local that steers later control flow
   becomes two functions or an early return.
5. Shared context is one value. Seven or more parameters, or one group of
   parameters threaded through several helpers, becomes a record or the
   receiver of `Type._helper` methods.
6. Results are return values. A status code plus an out-parameter becomes a
   return value and `raise` when the sentinel cannot collide with data.

Names

7. Length follows scope, as the bands say. Subject parameters keep the
   existing type-letter rule.
8. A helper name omits what its file or section already says. In
   `protocol.x`, `_generate_ordinary_protocol_adapters` becomes
   `_ordinary_adapters`.
9. One concept has one name everywhere. The glossary lists the shared roles
   and the only allowed abbreviations.

Incidental work

10. Each kind of incidental work has one place: a helper, a system macro, or
    a section. Examples: `$fail` and `_bad_form` in the literate Lisp;
    `_stat` and `_open` in `lib/path.x`; `$let` and `$scope(&owner)`.
11. Reuse before writing. Code that repeats a job an existing helper, macro,
    or runtime operation already does calls that owner. When the owner is
    static in another unit, it moves to the unit that owns the concept. A
    stanza of three or more lines that repeats three or more times gets one
    owner: a helper, a macro, or a table.
12. Delete before reshaping. Unreachable branches, uncalled functions, and
    checks of facts a producer established go first.

Files

13. One subject. The header states it and the invariant a reader would
    otherwise miss.
14. Reading order: representation; the central operation, which is the reason
    to open the file; the concepts it uses, in the order it uses them;
    incidental work; lifecycle and entry points last.
15. Top-down inside a section: the section's main function first, then its
    helpers in first-use order. Macros and types still precede their first
    use. Generated C already declares every static function before the
    definitions, so function order is free.
16. A section opens with a lower-case label. A concept that needs it gets up
    to three sentences in the same block comment.
17. Functions of one family look alike and sit together: the same
    parameter order, the same layout, and the order of the dispatcher that
    calls them. A family of one-line functions forms an aligned table.
18. A file with two subjects splits: into a new unit when the parts have
    different owners, or into parts of a unit directory (Track H) when they
    share one owner.

The line rules in `agents/x2c-coding-style-guide.md` stay as they are.

One check ties the rules together: compare each element with the elements
around it. A 300-line function among 10-line ones, a 45-character name
among 8-character ones, or a side effect buried in a condition is the
defect, whatever its absolute size.

### Glossary

| Role | Name |
| --- | --- |
| subject: Compiler, Emitter, Tokenizer, Build, Frontend, Sym | `c`, `e`, `t`, `b`, `f`, `s` |
| AST List under inspection | `node` |
| expression, statement, declaration node | `expr`, `stmt`, `decl` |
| a node's type; a conversion's destination | `type`, `target` |
| call arguments; declared parameters | `args`, `params` |
| operator; signature; callable value | `op`, `sig`, `fn` |
| count; indexes; cursor pointer; output | `n`; `i`, `j`; `at`; `out` |
| Token where a construct starts; origin table index | `origin`; `occurrence` |

`result`, `value`, `tmp`, and `data` stay banned across a nontrivial
function. `old_`, `saved_`, and `previous_` locals disappear with `$let`.
The pilot confirms or corrects this table before the waves use it.

### Review card

A reviewer answers these for each file:

1. Does the header state one subject?
2. Do the sections follow reading order, each opened by a label?
3. Is every function inside the bands, or a table or one-line-arm
   dispatcher?
4. Does each function stay at one level, guards first?
5. Do recurring parameter groups travel in a record or receiver?
6. Do names follow the glossary, with no subject repeated in helper names?
7. Does each kind of incidental work have one place?
8. Does the file call existing owners instead of re-spelling their work?
9. Do repeated shapes look identical and sit together?
10. Is every branch reachable and every check needed?

### Evidence

The standard comes from code Gary rewrote or held up as a model.

- The literate Lisp rewrite, 13 commits from 2026-09-12 to 09-20, turned
  53 functions with 788 lines into 63 functions with 532 lines. Mean
  function length fell from 14.9 to 8.4 lines, and the longest function
  from 76 to 50. Its moves, by the number of commits that used each:
  current idioms (7), full use of 79 columns (5), reading order with
  narrative sections (5), deleted temporaries and out-parameters (4),
  patterns in place of hand shape checks (4), one job per function with
  flags removed (3), `=>` bodies (3), deleted scaffolding (3), tables and
  one owner per convention (2), shorter names (2 commits, about 20
  renames, all shorter), and a line budget (2).
- The best runtime files: `lib/symbolset.x`, `lib/exception.x`,
  `lib/path.x`, `lib/split.x`, and `lib/atom.x`. Their functions average
  7-10 lines and the longest is 15-22.
- The best compiler regions: the productions in `src/statements.x`, the
  precedence ladder in `src/expressions.x` (lines 2650-2784),
  `src/cache.x` lines 474-590, and `src/deps.x`.
- Rules Gary added to the style guide since 2026-09-05: 79 columns as
  usable space, short control flow on one line, declaration rows, subject
  letters where they save lines, bare literals, `in`, and `$scope`.
- Gary's standing corrections: shorter code; "when in doubt choose less
  code"; a 14-row table a reader checks at a glance beats generated
  constructors.

The production Lisp shows the gap. `_apply_special` (`lib/lisp.x:1696`,
104 lines) is a `switch` that repeats a four-line arity stanza in six arms.
The literate Lisp's `Interp.special` does the same job with one-line arms
and one `_bad_form` helper.

## Where the code is ugliest

Baseline at `f6606dbf` over top-level functions in `src/*.x` and `lib/*.x`,
excluding generated `lib/x2c.x`:

| Measure | src/ | lib/ |
| --- | --- | --- |
| functions; median length | 2,114; 9 | 1,881; 6 |
| functions over 40 / 60 / 100 lines | 155 / 65 / 20 | 36 / 8 / 4 |
| share of lines inside functions over 40 lines | 27% | 8% |
| functions at brace depth 5 or more (body = 1) | 68 | 5 |
| functions with 7 or more parameters | 37 | 4 |
| function names of 25+ characters; mean name length | 217; 16.9 | 58; 10.6 |

Files ranked by lines inside functions over 40 lines:

| File | Lines | In long functions | Worst functions (lines) | File-level defect |
| --- | --- | --- | --- | --- |
| src/expressions.x | 4,420 | 1,856 (42%) | `_resolve_content` 398, `convert_expression` 333, `_convert_composite` 156 | parser, resolver, conversion, and initializer layout in one file |
| src/transform.x | 4,517 | 1,404 (31%) | `_step` 176, `_lower_captured_lambda` 140, `_lower_printf_vars` 124 | about 12 concepts; cleanup lowering in three places |
| src/macros.x | 4,777 | 1,272 (27%) | `parse_macro_definition` 302, `_import` 161, `_parse_target_definition` 133 | about 13 concepts under a header that names two |
| src/protocol.x | 2,584 | 1,063 (41%) | `parse_protocol_declaration` 131, `_publish_protocol_adoption` 108 | no section labels; visibility helpers that other files own |
| src/parse.x | 2,998 | 1,057 (35%) | `bind_syntax` 512, `parse_top_level_mode` 124 | the generated-syntax binder appended after the driver |
| src/emit.x | 1,267 | 482 (38%) | `Emitter._emit` 246, `_local_static` 104 | four stacked dispatchers in one function |
| src/literals.x | 1,267 | 467 (37%) | `parse_lambda_literal` 85, `bind_lambda_expression` 80 | |
| src/compiler.x | 3,997 | 462 (12%) | `full_parse` 115 | about 13 concepts; one label spans 1,750 lines |
| lib/match-machine.x | 571 | 270 (47%) | `MatchMachine.step` 270 | |
| lib/tokenizer.x | 843 | 278 (33%) | `_layout` 157, `_lisp_tokens` 64 | the driver sits under the wrong label |
| src/main.x, build.x, cli.x, project.x, meta-project.x | 628-1,209 | 25-47% | `Build.finish` 104, `CliRequest.prepare` 94, `_parse_command` 80 | |
| lib/string.x, lisp.x, error.x, match.x | 1,327-2,686 | 7-14% | `String.format` 119, `_apply_special` 104 | one API split across distant regions; helpers 700-2,300 lines from their callers |

The recurring defects:

1. Long dispatchers. `bind_syntax` has about 40 arms and 24
   `goto construction_error` exits. `_resolve_content` has 44 arms and
   repeats one deferral test 17 times. `Emitter._emit` stacks a list loop,
   a prefix loop, a 36-arm `match`, and a 33-case `switch`.
   `MatchMachine.step` has about 35 opcode arms of 1 to 24 lines.
2. Multi-phase monoliths. `convert_expression` is a 30-step `if` chain
   whose order is the specification. `_file` in `src/collect.x` mixes a
   directive scanner, segment flushing, declaration defaults, retention,
   and publication.
3. Parameter lists that carry shared context. `_definition` in
   `src/macros.x` takes 14 parameters; `_flush_segment` and
   `_parse_segment` in `src/collect.x` take 12 each.
4. Hand-expanded idioms. `src/` has 16 `Scope.push` pairs against 2
   `$scope(` uses, and about 18 manual save-and-restore sites that `$let`
   covers.
5. Re-spelled owners. The contextual-keyword test is written inline 16
   times, while `_test_contextual` (`src/parse.x:1706`) does the same job
   but is static in `parse.x`. The preprocessor arm-state encoding is
   written twice, in `src/compiler.x:842` and `src/collect.x:517`. In the
   literate Lisp, one `$fail` macro replaced 23 hand-built raises.
6. One concept under many names. The compiler parameter is `compiler` 485
   times, `c` 439 times, and `_` or `cc` elsewhere. An AST parameter is
   `ast`, `node`, `expression`, `expr`, `syntax`, or `input`. `rtype`,
   `return_type`, and `result_type` name one role.
7. Hidden dead code, verified on this tree:
   - `Compiler.shared_definition` (`src/macros.x:1309`) and
     `Compiler.region_no_lifetime_effect` (`src/regions.x:1285`) have no
     callers anywhere in the repository.
   - `case <threaded>` at `src/emit.x:1229` never runs. The storage-class
     branch at line 1004 consumes `threaded` first, and that arm's comment
     describes the live spelling at line 1015.
   - Four `return expr;` statements in `convert_expression` (lines 4187,
     4198, 4213, 4266) follow `report_error`. It raises the shared cause
     `<malformed>` or exits, so it never returns.

   Public runtime functions without callers (`File.putw`, `File.getw`,
   `File.setlinebuf`, `File.scanf`) and public functions called only by
   tests (several `scan_*` variants, `List.concat_n`) are Gary's decision.
   The campaign lists them and removes none on its own.

## How one file is beautified

A new skill, `beautify-x2c-source`, holds this procedure. One worker owns
one file.

1. Read the whole file, its tests, its callers, and the existing owners it
   could call instead of repeating their work.
2. Write an outline in the worker's notes: the subject in one sentence, the
   sections in reading order, and one line per function. A function whose
   line needs "and" is marked for splitting.
3. Measure with `x2c lint --all` including the new shape candidates, and
   read the wave's coverage report for the file.
4. Delete uncalled functions, unreachable arms, and redundant checks, each
   confirmed by reading callers and producers.
5. Reshape functions: dispatcher arms become named helpers; phases become
   named steps; flags become separate functions; threaded groups become a
   record or receiver; re-spelled work calls its existing owner; repeated
   stanzas get one owner; hand-expanded idioms become system macros.
6. Rename with the glossary.
7. Reorder the file into the outline. Write section labels and short
   section paragraphs.
8. Run the comment pass from `clean-x2c-source`.
9. Verify:
   - `make build`, then the fixtures and unit suites that exercise the file.
   - Once per file, `make stage-1 && make stage-diff-1`. Stage 0 is the old
     compiler's translation of the new source; stage 1 is the new
     compiler's translation of the same source. Byte equality proves the
     change left emission unchanged for all of `src/` and `lib/`. A
     difference is a behavior change to fix, never to rebaseline.
10. Record `.x` lines deleted and added, the shape measures before and
    after, and each neutral algorithm tweak with its reason.

Rules for every file:

- Public runtime names and signatures change only with Gary's approval.
  Compiler methods are provisional API; a rename updates its callers in
  `commands/` and the generated compiler API.
- No new validators, diagnostics, or negative fixtures.
- On a measured hot path, a new helper gets no `defer`, `$scope`, `$let`,
  or `$auto` without a paired measurement. One `defer` in a promotion
  helper once cost 3%, and `Ast.walk` cost 8.5%.
- When a move is large, move a function and change it in separate commits,
  so review can see the change.

## Order of work

| Wave | Scope | Reason | Checks |
| --- | --- | --- | --- |
| 0 | standard, skill, lint shape candidates, coverage probe | the waves use them | `make commands-check`; `doc-check` |
| 1, pilot | `src/collect.x`, `lib/tokenizer.x` | medium size, quiet since 09-27, outside the macro campaign, most defect classes present | per-file stage-diff-1; batch gate; performance checkpoint |
| 2 | driver: `build.x`, `cli.x`, `main.x`, `project.x`, `frontend.x`, `meta-project.x`, `generate.x`, `toolchain.x`, `install.x`, `utils.x`, `report.x`, and the small files `editor.x`, `script.x`, `deps.x`, `sourceview.x`, `meta-helper-client.x` | independent, low churn, parallel workers | per-file stage-diff-1; batch gate; checkpoint if `generate.x` changes |
| 3 | runtime: `match-machine.x`, `machine.x`, `string.x`, `error.x`, `scan.x`, `match.x`, `meta.x`, `lisp.x`, `var.x`, `varops.x`, `varconvert.x`, `pool.x`, `buffer.x`, `block.x`, `list.x`, `dispatch.x`, `func.x`, `scope.x`, `iter.x`, `file.x`, `logger.x`, `process.x`, `thread.x`, `path.x`, `regex.x`, `diff.x`, `datum.x` | hot paths need measured batches | unit suites; stage-diff-1; checkpoint per batch |
| 4 | front end and core: `compiler.x`, `parse.x`, `macros.x`, `stage.x`, `meta-group.x`, `builtins.x`, `linked-meta.x`, `ast.x`, `type.x`, `type-ledger.x`, `literals.x`, `statements.x` | shared with the dual-macro campaign | as wave 2; checkpoint per batch |
| 5 | semantics and output: `expressions.x`, `transform.x`, `protocol.x`, `emit.x`, `regions.x`, `cache.x`, `diagnostics.x`, `format.x` | files the dual-macro campaign changes now | as wave 4 |
| H | unit directories | spec after the pilot; code before wave 4 | one fixture; gate |

The pilot delivers the two rewritten files with before-and-after measures.
Gary reads them and says whether they meet the standard. The standard and
glossary change from his answer before Wave 2 starts.

Expected pilot shapes, to be confirmed by each file's outline:

- `src/collect.x`: representation (the process cache entry and a `Walk`
  record for one cold walk, replacing the 12-parameter threads); the cold
  walk as named steps (scan directives, flush a segment, splice an
  include); replay; declaration defaults for producing files; retention
  through one `_cache_scope` helper that replaces eight
  `Scope.push(&process_cache_scope)` pairs; include resolution; interfaces;
  entry points. The conditional-arm state machine that `compiler.x:836`
  repeats gets one owner.
- `lib/tokenizer.x`: representation; `Tokenizer.scan` and the C scanner;
  the Lisp-shaped modes with `_lisp_tokens` split into punctuation, atom,
  and splice helpers; the indentation layout as a `_Layout` record that
  owns its eight arrays and runs named passes; labels that match their
  sections.

Coordination with the dual-macro campaign. Its remaining steps rewrite
`transform.x` lowerings and protocol helper synthesis, then every raw
`%()` recognition of parsed nodes outside the grammar and parser. That
covers the dispatchers of Waves 4-5. Before claiming a shared file, the
beautification orchestrator agrees on ownership with the campaign's
orchestrator, as `orchestrate-x2c-work` requires. The default split: the
beautification first turns each large dispatcher's arms into one-line calls
to named helpers, a pure refactor, so the campaign's later recognition
change edits one line per arm. Reordering a shared file waits until the
campaign's handoff releases it.

## Wave 0 details

- Style guide: add a "Shape" chapter with the bands, rules, comparison check,
  glossary, and review card. Change the slice example under "Top-level
  order" to top-down order.
- Organization guide: remove the nonexistent `lambda.x` from the compiler
  module list. After Track H lands, allow unit-directory parts that share
  one owner.
- Philosophy exemplars: add `lib/path.x`, `lib/split.x`, and `src/deps.x`
  for reading order and one owner per failure spelling.
- Skill: `agents/skills/beautify-x2c-source/SKILL.md` with the procedure
  above and a reference page for the coverage probe, plus one routing line
  in `agents/README.md`.
- Lint: four `<style>` `<candidate>` rules in `commands/lint/structure.x`,
  built on the function token ranges `Lint` already holds:
  `long-function` (over 40 lines), `deep-nesting` (brace depth 5 or more),
  `long-parameter-list` (7 or more), and `long-name` (a defined name of 30
  or more characters). They are review candidates and join no gate.
- Coverage probe: in a scratch worktree, translate a stage with
  `--source-map`, compile and link it with clang's
  `-fprofile-instr-generate -fcoverage-mapping`, run the unit suites, the
  compiler fixtures, and one self-translation of `src/`, then report
  never-executed `.x` lines per function with `llvm-profdata` and
  `llvm-cov` (both present under Xcode). It runs once per wave. Its output
  lists candidates; each deletion still needs a caller check.

## Track H: unit directories

Recommendation: yes. Add one convention. A directory whose name ends in
`.x` is one translation unit. `src/macros.x/` holds its head `macros.x`
and any number of other `.x` parts. The unit is the head followed by the
other parts in bytewise name order, exactly as if they were one file, so
every part sees every private declaration. Nothing else changes:
`#include "macros.x"` names the unit; generated `macros.c`, `macros.h`, and
`macros.xi` keep their names; the `src/*.x` wildcard in `builds/stage.mk`
already matches the directory; `bootstrap/` keeps its file names; packages
and `import` are untouched. The directory name is the whole convention.

Reasons:

- A beautiful file has one subject. Today a coherent unit splits only by
  exporting its shared helpers, which puts them in the generated header and
  the provisional compiler API. `src/` exports about 680 functions against
  about 1,460 static ones, and a rough count finds about 370 exported
  functions used by exactly one other compiler file.
- Three of the four largest files (`macros.x`, `transform.x`,
  `compiler.x`) hold 12-13 concepts each. As unit directories they become
  one part per section, each a few hundred lines.
- A split is provable. Generated C carries no source positions unless
  `--source-map` is on, so splitting a file at section boundaries, with
  part names in the original order, yields byte-identical C.
- Only macros and types must precede their use, and they belong in the
  head.

Semantics to specify:

- The head is the part named after the directory. It holds the module
  header, public declarations, `#pragma private`, shared private types, and
  macros.
- The other parts follow in bytewise name order. An include in a part
  resolves as it would in the head, relative to the directory that holds
  the unit.
- Every part uses the head's syntax: `.x` parts in a `.x` unit and `.xp`
  parts in a `.xp` unit. Other files in the directory are not part of the
  unit.
- Diagnostics, `--source-map` line markers, `--dump-definitions`, and the
  editor adapter report the part file and its own line numbers.
- The unit's `.d` depfile and `.xi` interface list every part.

Implementation owners, each narrow: `x2c_source_file` and input
validation (`src/utils.x`, `src/main.x`, `src/build.x`); `read_source`
through `SourceView`, which returns the head and parts as one text with a
part table; `Compiler.token_location` and the origin rows, which map a
byte position to its part; the line-marker writer in `src/format.x`;
include search in `src/collect.x`; depfile and interface dependencies;
manifest glob matching; `builds/stage.mk` prerequisites; `x2c lint`,
`x2c graph`, `tools/gen-api-reference`, and `tools/repo-metrics.py`. The
estimate is a few hundred lines.

Sequence:

1. H1: write the book text, a "Unit directories" subsection under "Source
   files and pragmas" in `docs/src/reference/language.md` and the input
   rules in `docs/src/reference/cli.md`. Gary approves the text before any
   code.
2. H2: implement it with one compiler fixture: a diagnostic located in a
   part, a static helper shared across parts, and an includer that sees
   only the head's public declarations.
3. H3: after a large file's wave reorders it into sections, split it into
   parts, first with order-preserving names to prove byte-identical C,
   then with plain names.

Not recommended: subsystem directories of ordinary units, such as
`src/front/parse.x`. They change every include line and every path in the
docs and tools, the flat `--out-dir` rejects duplicate basenames, and
shared helpers still have to be exported. Unit directories give smaller
files without those costs.

## Verification and delivery

- Per file: the checks in step 9 of the procedure.
- Per batch: the orchestrator integrates the workers' commits, reviews the
  combined authored diff, and runs `tools/land-dev` once. In its
  precommit, `stage-diff-0` must pass on the first round, because a pure
  refactor leaves emission unchanged. Fixture sidecars stay unchanged; any
  sidecar change is reviewed as a possible behavior change.
- Batches that touch the runtime or the compiler core run the performance
  checkpoint in `agents/performance-checkpoints.md` before publication.
- Delivery goes to `dev` as the root `AGENTS.md` describes. Commit subjects
  name the file and the change, such as
  `split the collect walk into named steps`.
- Reports lead with `.x` lines deleted and added per file, then the shape
  measures.

## Done when

- `src/` reaches `lib/`'s current profile or better: under 8% of lines in
  functions over 40 lines, no function at brace depth 5 or more, none with
  7 or more parameters, and no function name of 30 or more characters
  except fixed public names.
- Every `src/` and `lib/` file passes the review card.
- If Track H is approved, no source file over 1,500 lines remains outside
  a unit directory.

## Out of scope

- Algorithm and data-structure changes beyond neutral tweaks.
- Deleting or renaming public runtime API without Gary's decision.
- Generated files and `bootstrap/`, which the gate regenerates.
- `examples/`, `packages/`, `unittest/`, and `commands/`. A later campaign
  can apply the same standard there.

## Plan review

- Trusted facts. Stage comparisons establish emission equality for `src/`
  and `lib/`, fixtures establish other programs' output, and unit suites
  establish runtime behavior. The campaign adds no check that repeats
  them. Shape findings are review candidates and join no gate.
- Reuse and deletion. The procedure reuses `clean-x2c-source`,
  `simplify-x2c-source`, `find-redundant-validation`, the lint function
  table, the stage targets, `tools/land-dev`, and the performance
  snapshot. It deletes dead code and repeated stanzas as it goes. The new
  lasting pieces are one style-guide chapter, one skill, four lint
  candidates, and, if approved, unit directories. They answer, in order:
  no written shape standard, no procedure between local cleanup and
  deletion, no measure of function shape, and no way to split a coherent
  unit without exporting its helpers.
- Idiom. The rewrites use current x2c: `match` dispatch to receiver
  helpers, records, `$scope`, `$let`, tables, and `=>` bodies. Unit
  directories are one naming convention over the existing unit model.
- Validators, diagnostics, and negative fixtures: none in the
  beautification. Track H adds one positive fixture for its public
  semantics.
