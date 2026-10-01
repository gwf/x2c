# x2c Source Organization

> Status: active. Gary approved the plan on 2026-09-30, written against
> `dev` 2685655f. Phase 1 (rules, guide corrections, plan archive) and the
> merge of `main` back into `dev` are delivered; Phase 2 is in progress.

## Result

Every hand-authored file in `src/` and `lib/` has one subject, stated in
its header, and reads top to bottom in the order the style guide gives.
Each fact has one owner. Each context record owns the operations that use
it. Files split where a part has its own owner, a one-way dependency, and
its own tests, and nowhere else. Six reproduced defects are fixed first.
Behavior, public names, and generated-code contracts stay the same, except
where a defect fix restores documented behavior.

The function-level work from Waves 0-5 stays. Function height does not
drive this plan.

## Why the waves left this

The original campaign stated the file rule. Rule 18 of
[x2c-beautification.md](archive/x2c-beautification.md) says "A file with two
subjects splits into new units when the parts have distinct owners", and its
baseline table lists the file-level defect of each large compiler file. The
wave tables then measured only lines, functions, longest function, functions
over 40, and parameters. No column tracked owners or subjects, every file
split went to a "Candidates left for later" list, and Track H was retired
with nothing in its place. The guides now disagree: the style guide calls a
file over 1,500 lines with several owners "too much", and the organization
guide forbids a split "solely to shorten". The beautify skill has no
file-level step.

Baseline at 2685655f, over 94 hand-authored `.x` files (excluding
`lib/x2c.x` and `src/linked-meta.x`):

| Measure | f6606dbf | 2685655f |
| --- | --- | --- |
| Lines | 71,648 | 77,447 |
| Functions over 40 lines | 190 | 11 |
| Functions with 7 or more parameters | 41 | 8 |
| Files over 1,500 lines | 9 (29,833 lines) | 9 (32,839 lines) |
| Sections over 400 lines | - | 11 |
| Private records | 97 | 172 |

Files over 1,500 lines: `src/macros.x` 5,538, `src/transform.x` 4,965,
`src/expressions.x` 4,952, `src/compiler.x` 4,335, `src/parse.x` 3,337,
`src/protocol.x` 2,861, `lib/match.x` 2,815, `lib/lisp.x` 2,185,
`lib/string.x` 1,842.

## Settled choices

### The file rule

A file over 1,500 lines is a review trigger, not a split order. The review
lists the file's subjects and measures each candidate boundary by the
private helpers that would cross it in each direction. A part splits into
its own unit when it has a distinct owner, depends on the rest in one
direction, and has its own tests. A file with no such boundary keeps its
size; its header names its one subject and its sections follow reading
order, each under 400 lines. A helper that crosses a new boundary becomes a
method of the owner that establishes its fact. It never becomes a new
`x2c_*` export.

Phase 1 writes this rule into the organization guide, points the style
guide's File row at it, and adds a file-level first step to the
beautify skill.

### The record rule

A private record that carries the state of one operation owns that
operation: its steps are `Record._step(Record *r, ...)` methods. A record
whose fields are copied into locals on entry is a parameter list and goes
back to parameters (six or fewer) or becomes a receiver. A record's
Compiler field is `c`. A private record has a bare PascalCase name; the
leading underscore marks private functions only. One concept has one
record: `CallbackBuild`, `LambdaAdapter`, and `TypedAdapter` in
`transform.x` become one.

Phase 1 writes this rule into the style guide under "Names expose
ownership" and adds it to the beautify skill's review card.

### Splits

Each row passed the split test above. Coupling is static helpers crossing
the boundary, out/in.

| From | New unit | Contents | Lines | Coupling |
| --- | --- | --- | --- | --- |
| src/compiler.x | src/symbols.x | `Sym`, `SymTxn`: scopes, definitions, bindings, transactions, typedefs (`struct Sym` at 234; 1211-2486) | ~1,280 | 0/1 |
| src/compiler.x, src/ast.x | src/preprocess.x | directives, conditional arms, leading directives (840-1210) and the `preproc_*` family from ast.x 242-300 | ~430 | 1/2 |
| src/transform.x | src/callables.x | tadapt, Func adapters, lambda cells, capture environments (40-1915) | ~1,870 | 1/0 |
| src/transform.x | src/cleanup.x | cleanup regions, try, defer, goto, landing frames (1915-2970, 4238-4624) | ~1,440 | 0/1 |
| src/literals.x | src/lambdas.x | lambda parsing and binding (931-1386), plus `check_lambda_captures` and `lambda_param_types` moved from transform.x | ~550 | 0/0 |
| src/macros.x | src/meta-sdk.x | the compiler's answers to `lib/meta.x` operations (4814-5444) | ~630 | 2/8 |
| src/macros.x | src/meta-native.x | meta functions, explicit meta calls, native lifetimes, target inventory, linked definitions, native modules, linked extensions (3813-4814) | ~1,000 | ~10 |
| src/expressions.x | src/initializers.x | initializer paths, rows, and native layout (3440-4544) | ~1,100 | 1/1 |
| lib/match.x | lib/match-plan.x | lowering to a prepared plan (456-1285) | ~830 | 0/0 |
| lib/match.x | lib/match-cache.x | `MatchCache`, `MatchLease`, default caches (1867-2429) | ~560 | 2/1 |
| lib/string.x | lib/string-format.x | `String.format`, `_Spec`, `_Format` (1246-1552) | ~310 | 0/0 |
| lib/string.x | lib/string-escape.x | escapes and C-literal spelling (1553-1796) | ~245 | 0/2 |
| lib/meta.x | lib/macro-value.x | macro values called from generated code (384-1040) | ~660 | 0/0 |
| lib/lisp.x | lib/lisp-targets.x (grown) | primitives and native targets (1120-1383, 1568-1887) | ~590 | via `_native_target` |

`macros.x` coupling to `meta-sdk.x` falls to zero when `_sdk_guard`,
`_sdk_reject`, and the context statics move with it. `meta-native.x`
crosses about ten helpers (`Definition.signature`, `_ensure_lisp`, and
others); each becomes a method of its owner. `string-escape.x` replaces its
two private crossings (`_finish`, `_free_unchecked`) with the public
`String.malloc` and `intern_free`, measured on the hot emission path in
Phase 4. `string-format.x`, `string-escape.x`, `match-plan.x`,
`match-cache.x`, and `macro-value.x` join the prelude because the
operations in them are prelude operations today or are called from
generated code; `docs/library-manifest.txt` gets a row for each.
`lib/meta.x` keeps the compile-time surface.
`MatchMachine.open` and `dispose` move from `lib/match.x:2789-2815` to
`lib/match-machine.x`, which `match.x` already includes.

These stay whole, with section repairs only: `src/parse.x` (constructed
syntax reuses its private declaration operations, 11/14 crossings),
`src/protocol.x` (one feature owner from parse to adapters; adapter
generation uses 23 of its helpers), the remaining `src/macros.x`
definitions-to-expansion core (8/11), the `_parse_*`/`_resolve_*` families
of `src/expressions.x` (12-18), `lib/error.x` (the catch ABI needs its
private records), `lib/var.x`, and `src/utils.x` (six small subjects; a
file per subject would be "a file for one helper").

After the splits, these files remain over 1,500 lines with one stated
subject each: `macros.x` (~3,900), `expressions.x` (~3,850), `parse.x`,
`compiler.x` (~2,690), `protocol.x`, `transform.x` (~1,650), and `lisp.x`
(~1,600). Their sections are repaired in Phase 5.

### Defects

Each was reproduced at 2685655f.

1. Optional runtime modules leak into the prelude. `lib/lisp.x:84-87`
   includes `process.x`, `regex.x`, `typed-array.x`, and `typed-map.x`
   below its pragma, so a program with no include can name `Regex`, `Job`,
   or `ArrayInt`; x2c accepts it and clang fails with `unknown type name`.
   The compiler replays an included file's private includes on purpose
   (`src/collect.x:179-183`): a unit may call the functions they declare,
   and 17 compiler units depend on it. A type reached that way fails in
   clang instead of x2c, which is a later error, not wrong output, so the
   replay stays. The runtime fix moves `lisp.x`'s bindings of those four
   modules (the Job adapters near `lisp.x:1654-1665` and the target rows)
   into `lib/lisp-targets.x`, the way Json, Diff, and Path are kept out.
   That is the `lisp.x` split in Phase 4, so it lands there.
2. `lib/meta.x`'s header and its manifest row say it is outside the
   prelude, but every unit reaches it through `varops.x:14`, and the
   documented one-line import of `system-macros.xmacro`
   (`docs/src/guide/system-macros.md:416-423`) depends on that, because its
   `meta` functions call `x2c_literal_string` and its neighbors. Correct
   the header and the manifest row to say how the module is reached. No
   code changes.
3. Lisp standard operations lost their argument check. `cbb357f8`
   (2026-09-26) moved them to `lib/lisp-init.x`, which calls typed
   operations directly instead of through the Func adapter.
   `(string-append "a" 1)` returns `"a"`; `(search-replace 5 'a 'z)`
   returns `()`. Both raised `bad-types` before, and the `lisp-init.x`
   header promises each operation follows the definition it replaced.
   Conversion of a wrong tag to `String` or `List` yields NULL by design
   (`docs/src/guide/values.md:132-134`), and a typed `foreach` binder does
   the same, so the check belongs in `lisp-init.x`: one private reader per
   object tag that raises the same `bad-types` detail as
   `x2c_func_value_argument`, as list walks already do through `lisp_car`.
   Audit all 31 operations against `cbb357f8^:etc/init.xlisp` with one
   wrong-type case each, and add the failing cases to `test-lisp.x`.
4. A local assigned inside `try` is emitted `volatile`; passed to a `&`
   parameter it becomes `&(status)` at an `int *` parameter, which drops
   the qualifier (C11 6.7.3p6). Seen live in
   `commands/graph/x2c-graph.x:3176-3185`. The fix also found a
   miscompile: a local written only by a callee is not `volatile`, so a
   callee that writes it and raises loses the write at `-O1` and above
   (`x2c run -O2` prints `only=0`; `-O0` prints `only=5`). A local whose
   address a `try` body passes to a call now keeps its plain type, and its
   declaration stores its address in the thread-local
   `x2c_exception_escaped` (`lib/exception.x`), so C must assume every call,
   `sigsetjmp` and the raise included, reads and writes it. Locals that are
   not address-taken stay `volatile`.
5. The region check warns on `bind_ref(Env &local, ...)` and not on the
   same body written with `Env *local`. Both forms must give the same
   result. This is why `x2c lint` suggests `LispEnv &local` at
   `lib/lisp.x:716`, a change that then fails `--fatal-warnings`; after
   the fix that suggestion either compiles or is not made.
6. `tools/check-doc-examples:74-77` limits CPU time only; a sample that
   sleeps blocks `Job.wait_any` with no wall deadline and can stall
   `doc-outputs`. Add a wall deadline through the existing Job lifecycle.
8. Logger retention recurses once per cell of a flat List
   (`lib/logger.x:619-655`, `_retain_list` calls `_retain` on each cdr
   before consing), so logging a 200,000-cell List from a child pool to a
   memory sink crashes with SIGSEGV. Rebuild the spine iteratively, as
   `lib/context.x:208-222` does, keeping Logger's ancestor-pool identity,
   borrowed values, and sink lifetime. Found by the call-graph review.
7. `self-annotation-mismatch` reports its error at `int main` (line 11)
   instead of the definition (line 7). Its fixture checks only the compile
   status. Fix the location and pin it with a `.diagnostics` file.

### Duplicate owners

| Fact | Copies | Owner after |
| --- | --- | --- |
| SymbolSet perfect hash | encoder `src/literals.x:651-671`, decoder `lib/symbolset.x:54-91` | `lib/symbolset.x`; the encoder moves there and the compiler calls it |
| Self-relative method signature | Sym spelling store and binding facts (`parse.x:896-898`, `compiler.x:1467-1472`) | kept: the Sym row is the only store `.xi` interfaces carry to other units (`collect.x:352, 376`), and binding facts are filled from it per compiler (`compiler.x:1481`); removing it broke a two-unit `Self` method probe |
| FNV offset basis | `build.x:1161`, `utils.x:286`, `meta-group.x:77` (last digit dropped), `parse.x:273` | one constant beside `x2c_fnv_bytes`; `meta_cc_identity` calls `x2c_file_identity` |
| Exit status decoding | `src/utils.x:406`, `src/meta-helper-client.x:237` | `utils.x`; `lib/process.x:300` keeps its own because the runtime cannot call the compiler |
| Hex digit | `lib/json.x:186`, `lib/string.x:1679`, `src/type.x:767` | `lib/scan.x`, by making `_ascii_hex` a public `scan_ascii_hex` beside `scan_ascii_digit` (scan.x is internal) |
| Contextual keyword test | 13 copies in 5 files; static `_test_contextual` at `parse.x:397` | `Compiler.at_word` (non-consuming) and `Compiler.take_word` in compiler.x token navigation |
| Realpath or keep | `compiler.x:455`, `collect.x:483`, `protocol.x:34` | kept, with comments: under a source view `Compiler.canonical_path` makes a path absolute, while collect keys unsaved files by the searched spelling and protocol needs to know whether the first path resolved |
| Emitter recognition | `Emitter._emit` head switch plus six `_emit_*` groups that match again and return `matched` (`src/emit.x:1194-1399`, b796f4e1) | one `match` in `_emit` with one-line arms; delete the groups and the flag |
| List to Array copy | the copy loop in `List.array`, `append`, `sort`, `sort_with`, `sort_by` (`lib/list.x:322, 365, 734, 746, 759`) | `List.array`, after it cleans up a partial Array on failure; keep `append`'s shared tail and `sort_by`'s one key call for a one-element List |
| Nested-lambda presence | `ast_contains_head` at region entry and again on every child before descending (`src/transform.x:1437-1528`) | one identity-preserving visit that prepares regions and reports presence; measure deep-lambda and lambda-free cases |
| Open-template rebuild | `_template` discovers, then `_replace_bindings`, `_open_natives`, and origin `search_replace` each rebuild (`src/macros.x:2277-2338`) | one coordinated rewrite after discovery, if fixtures and stage equality prove it equal; otherwise record why the passes stay |
| Typed zero-pointer target | the same initializer-target template at `src/expressions.x:4490, 4536` | one constructor |
| Args repeated values | shared-name rows still append prefixes (`lib/args.x:147-150`); 200 values make 19,910 allocations against 201 | one accumulator per result name, keeping first-occurrence reset, defaults, mixed-row overwrite, and store order |

Kept on purpose, with the reason: the one-argument FuncArg stanza and the
fprintf/abort stanza are two lines each, under the style guide's three-line
threshold; the `_apply1`/`_apply2` pair in list.x and iter.x,
`_register_shutdown`, `_mutex_initialize`, and thread/mutex `_error` would
each need a new exported helper that widens the surface more than it saves;
UTF-8 validation in `src/cli.x` and `lib/json.x` has no existing public
owner, and adding one is a library change outside this plan.

### Surface

- `x2c_numeric_f32/f64/ldouble` (`lib/varconvert.x:34-36, 280-302`) and
  `x2c_mutex_recursive_*` serve ordinary x2c callers only and are not on
  `main`. Make them methods of `X2CVarNumeric` and `Mutex`. No released
  name changes.
- About 19 compiler-internal `x2c_*` functions in `src/utils.x` have no
  caller outside the compiler. Drop the prefix. Keep `x2c_set_root`,
  `x2c_get_root`, `x2c_get_executable`, and `x2c_initialize_*`, which
  commands call.
- `src/editor.x:12-20` and `src/main.x:10-17` move their private includes
  below `#pragma private`.
- Wrong-phase helpers: `record_declaration_visibility` and its helpers
  (`protocol.x:32-113`) move to `symbols.x`; `ast_collect_binding_references`
  moves from compiler.x to ast.x; the `meta-group.x:17-18` forward
  declarations of `Compiler.transform` and `generate_code_text` go away once
  `meta-native.x` owns the calls that need them, or the plan records why the
  cycle remains.
- Released test-only entries (`x2c_error_raise`, `x2c_register_type`,
  `x2c_error_catch_push`) stay; they shipped in 0.14.0.

## Phases

Each phase is one batch delivered to `dev`. A
call-graph review of 2026-09-30, made with `x2c graph` over the whole
production source, added defect 8 and the Phase 3, 5, and 6 items it names; it
argued against size-driven splits, which this plan does not make. Workers within a batch follow
`orchestrate-x2c-work`; the orchestrator integrates and gates once.

### Phase 1: rules and records (documentation only)

- Write the file rule and the record rule into
  `agents/x2c-code-organization-guide.md`, `agents/x2c-coding-style-guide.md`,
  and `agents/skills/beautify-x2c-source/SKILL.md`.
- Correct the organization guide's module lists (missing `clibc`, `cmath`,
  `match-machine`, `static-init`, `adapter-memo.xmacro`,
  `ast-rewrite.xmacro`), its `OPTIONAL_SOURCES` sentence, its
  `#pragma once` sentence, and "scope stacks use Arrays" (`Sym.scopes` is a
  Block). Fix `BUILD_LDFLAGS` in the development guide, `Var.box_i64` in
  `adapters-macros-decorators.md:478`, `Emitter._var_collection` in the
  Match guide, `unittest/STATUS.md:18-22`, the graph README test path, and
  the hash-table benchmark README target names.
- Archive the finished plans with their outcomes:
  `compiler-library-beautification-next.md`,
  `compiler-library-review-coverage.md`, `native-meta-execution.md`,
  `meta-integration-mitigation.md`, `macro-capture-role-consolidation.md`,
  `bug-findings-f28fc36.md`, `evaluator-and-source-consolidation.md`.
  Move `consolidation-catalog-f28fc36.md` item C13 to the backlog table and
  archive the rest. Mark `x2c-beautification.md` done with a pointer here.
  Refresh the index in `plans/README.md`.
- Validation: `tools/gate-state.py ensure doc-check`.

Delivered with the merge of `origin/main` into `dev` (`git merge -s ours`):
`main` held f28fc36f and the 45e5b445/247b7fbe pair, which cancels; `dev`
had rewritten every region f28fc36f touched, so the merge keeps `dev`'s tree
and restores the release ancestry check. The orphan fixture file moves to
Phase 2, which edits the fixtures.

### Phase 2: defects

One commit per defect, using `fix-x2c-bug`. Defect 1 lands with the
`lisp.x` split in Phase 4. Strengthen the fixtures that accept any failure where the
expected diagnostic is now known: `self-annotation-mismatch` (defect 7),
`macro-body-type-hole-ambiguous-pointer`, `meta-header-packed`,
`preprocess-missing-include`, and the three that accept any abort
(`block-growth-failure`, `buffer-embedded-nul`,
`raise-in-finally-unhandled`). Validation: `agent-pr-check`.

### Phase 3: one owner per fact and surface

The duplicate-owner table, the Args accumulator, and the Surface list.
One commit per row or connected group. The emitter routing change keeps
exact arities, the C-shaped fallback, and `_emit_leaf`; the deep operator
chain fixtures pin the native stack budget the `_operand` comment
describes, and they must pass unchanged. Validation: `agent-pr-check`.

### Phase 4: splits

Compiler splits first, then runtime splits. Each split is a move commit
with no edits inside the moved text, followed by a commit that turns
crossing helpers into owner methods and writes the new unit's header and
section order. New `src/*.x` units need no build edit (`etc/x2c.mk:27`
takes `$(SOURCE)/*.x`); new `lib/` units need `lib/Makefile` and
manifest rows. Run the performance checkpoint once for the batch: the build
cost score within its 4-point noise, and the bench lanes for String and
Match within noise. Validation: `agent-pr-check`.

### Phase 5: reading order and record ownership

For every file over 1,000 lines after Phase 4, and every new unit:

- The header names one subject. The central operation comes first, then
  the concepts in the order it uses them, incidental work, and lifecycle.
  `transform.x` starts with `Compiler.transform`, `_node`, and `_step`.
- Every section has a plain label and stays under 400 lines. `protocol.x`
  and `emit.x` get labels; `expressions.x` splits its 1,345-line section;
  decorated rulers (`/* --- try ---` and the four files the review listed)
  become plain labels.
- Records follow the record rule. The ~19 records that are unpacked on
  entry become parameters or receivers. `CaptureBuild`, `TypedAdapter`,
  the cleanup `Walk`, and the merged callable-adapter record own their
  steps. `Definition` keeps its receiver steps; its fields shrink to the
  state its steps share, and `publish` runs once.
- Private Compiler helpers become `Compiler._helper` methods where the
  Compiler is their dominant receiver, as the organization guide says.
  The same holds for the existing records the call graph names:
  `DeferCaptures` (`transform.x:4280-4333`), the regions `Walk`
  (`regions.x:78`), `Pool` (`pool.x:213, 306, 334, 404, 666`),
  `LogMemorySink` (`logger.x:619-655`), and the Context export family
  (`context.x:194-280`). Native callback trampolines keep their C
  signatures.
- `_node` (`transform.x:4937`) only forwards to `_step`; the dispatcher
  takes the `_node` name and the layer goes. `Func._new` reads
  `params.len()` once.
- The subject parameter and record field are `c`; private records lose the
  leading underscore.

Validation: `agent-pr-check`.

### Phase 6: commands and packages

- `commands/graph`: target classification, emitted names, and unique
  public targets are derived in `x2c-graph.x:28, 730, 1386` and again in
  `targets.x:24, 63`; `targets.x` owns them. The open, analyze, export,
  close stanza repeats in eight entry points near `x2c-graph.x:1202-1350`;
  one operation owns that lifetime. Keep each report's records, sorting,
  and output. The graph tests are the corpus.
- `packages/blis`: `copy_from`, `add`, and `sub` repeat the live-object,
  shape, and precision checks (`blis.x:525, 624, 646`); share one
  compatibility operation and keep each operation's error and fresh result.
- `packages/libuv`: TCP and Pipe repeat the connected, EOF, reading, and
  write-shutdown rules (`libuv.x:1476, 1505, 1683, 1712`); put them on
  `UvStream`, keeping typed callback wrappers and request lifetimes.
- Package changes land only after the package's own check runs with its
  prepared dependencies (`packages/Makefile`); a package whose dependencies
  cannot be prepared keeps its current source, and the plan records why.

Validation: `agent-pr-check`, `make commands-check`, and each touched
package's check.

### Phase 7: closing measure

Rerun the baseline analyzer on the final tree with the same file
selection and report the table above, the remaining files over 1,500 lines
with their stated subjects, and every section over 400 lines. Report
lines added and deleted in `.x` source. Update this plan's status and the
plans index.

## Done when

- No file over 1,500 lines has two subjects; each one's header names its
  subject, and the plan records why no boundary qualifies.
- No section exceeds 400 lines. Every large file opens with its central
  operation.
- Every row of the duplicate-owner table has one owner.
- No record is unpacked into locals on entry; one record convention holds
  across `src/` and `lib/`.
- The eight defects are fixed and pinned.
- Function bands hold: no more functions over 40 lines than the 11 today.
- Every phase passed its gate, and Phase 4 its performance checkpoint.

## Outside this plan

- A public function below `#pragma private` that returns a type from a
  private include puts its prototype in the generated header without that
  type's header, so any unit including the header fails in clang. Found
  during defect 1; it needs its own `fix-x2c-bug` pass.
- `try return f(); catch ...: return g();` generates C that clang flags
  with `-Wreturn-type` (seen in `tools/check-doc-examples` `_stdout`); every
  path returns at run time. Found during defect 6.
- Defect 6 ends a timed-out sample's own process, not its process group:
  Job runs children in the caller's group, and a per-job group would be a
  new `process.x` option that also stops Ctrl-C reaching samples.
  `preprocess-missing-include` keeps its status-only check, because its
  stderr carries the host C compiler's own message.
- The region check treats a pointer cast to `int` and returned as a
  returned address (`return (int) value;`). Found during defect 5; it
  needs its own `fix-x2c-bug` pass.

- The unwired tests other than those Phase 2 wires
  (`bound-template-expression.c`, `source-call-projection.x`,
  `tools/test-examples.py`, `tools/test-performance-snapshot.py`) stay
  manual. Gary approved wiring `run-meta-transport.sh`,
  `run-meta-source-kinds.sh`, and `commands/graph/tests/certify.sh` into
  their existing runners in Phase 2.
- Command builds use no `-Werror`; defect 4 removes the one C warning.
- The release: the version is still 0.14.0. Release work follows
  `agents/releasing.md`.

## Plan review

- Established facts and rechecks: Lisp argument tags are established by the Func
  adapter for bound operations; defect 3 adds the same check only where
  `lisp-init.x` bypasses that adapter, matching what `lisp_car` already
  does. No other phase adds a check.
- Deletion and reuse: the emitter's six group dispatchers and `matched`
  flag, the Sym signature store and one `_receiver_relative_signature`, the
  compiler's SymbolSet encoder copy, three FNV constants, one exit-status
  decoder, two hex readers, twelve contextual-keyword tests, two realpath
  helpers, the shared-name prefix append in Args, the parameter-bag
  records, two of three callable-adapter records, and four Lisp binding
  mechanisms reduced to one. New units hold moved code; the only new
  operations are `scan_ascii_hex`, `Compiler.at_word`, and
  `Compiler.take_word`, each replacing existing copies.
- Idiom: the result uses existing x2c units, receivers, `match`
  dispatchers, and the prelude. It adds no registry, framework, or
  generated layer.
- Validators and fixtures: defect 1 adds no check; the leaked types still
  fail in clang, and the runtime move removes the leak. Defect 3's `bad-types` restores the documented
  contract of `lisp-init.x` and prevents wrong values. Defect 4 prevents an
  unsafe native crossing. The new `.diagnostics` expectations pin existing
  diagnostics; they add no diagnostic.

Each phase ends implementation with a review of the completed authored
diff for the same points, fixed before the publication proof.
