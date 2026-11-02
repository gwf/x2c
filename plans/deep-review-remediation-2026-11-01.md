# Deep review remediation (2026-11-01)

> Status: active - batch A published on `dev` as `9d196566f` (PR #643,
> 2026-11-02); batch B runs in its own session; batch C integrated from
> `dev` `9d196566f` and submitted to the shared integrator on 2026-11-02 on
> branch `gwf/review-batch-c-contracts`, with the decisions below.
> The review record is workspace-local
> (`.context/repository-review-2026-11-01.md` in the reviewing worktree);
> this plan carries the decisions and the batch map.

## Requested behavior

Repair what the 2026-11-01 whole-repository review reproduced at `dev`
`251979316`: compiler miscompilations and crashes, runtime defects, test
harness defects, and documentation that contradicts the implementation.
Then remove the verified waste and settle the contracts that the review
found applied several ways. Gary selected this session for the work with
Opus workers; delivery follows the root default, ready PRs to the shared
integrator with focused evidence.

## Decisions taken in this plan

- A public `inline` function that names a unit-private function is a
  compile error (C11 6.7.4p3). Compiler-generated helpers that a public
  inline body may reach (String switch, protocol update and discard
  helpers) get external linkage with path-hashed names, as lambda bridges
  already do.
- Hole names apply inside every quoted form, List and String data
  included, as they already do in Array and Map quotations.
- The `lisp.*` macro namespace is reserved like `x2c.*`, as the reference
  already states.
- String constructors that cannot represent their result raise
  `<size-limit>` (ER-1); returning the empty String is removed.
- Lisp string tokens use the x2c escape rules that `%(...)` strings use;
  the C escape validator applies only to C literals.
- Fixed recursion limits consult the installed execution-stack allowance
  and raise their existing causes instead of overflowing a task stack.
- A moved function body is placed before a later `#define` or `#include`
  that could change its conditional arms, as an `#undef` already is.
- Block-pointer declarators (`^`) are rejected with a diagnostic rather
  than emitted as internal words; C11 `_Alignas`, `_Atomic`, and `_Complex`
  are accepted and emitted verbatim.
- Wide scalars converted to a Var inside a region count as allocations
  for lifetime checking; the allocator table gains the missing runtime
  rows, including `move_to`.

## Decisions for batch C (accepted by Gary on 2026-11-02)

1. Boxed `Array` writes that cannot be performed (`setindex`, `push`,
   `unshift`, and `insert` on a null array or an out-of-range index) raise
   `<bad-arg>` like the compound forms and typed Arrays; reads keep
   returning `void`.
2. A required `iter.x` callback that is null raises `<bad-arg>` when the
   operation is called, before any source element is consumed; `zip_with`
   keeps its documented optional `fn`.
3. Null handles: an operation on a null handle raises `<bad-arg>`; `free`,
   `close`, `destroy`, and `cleanup` accept a null handle and do nothing;
   causes that describe a non-null handle's state stay `<bad-state>`.
4. List and Array search (`index`, `contains`, `count`, `assoc`) keep `==`,
   and the doc comments and the book say so; `Map` keys and `unique` use
   `Var.equal`.
5. `protect_x2c` leaves the Lisp runtime; `def` of an `x2c.` name follows
   the ordinary inherited-name and frozen-session rules.

Batch C runs as four workers with disjoint files: collections (1 and 4),
iter (2), handles (3), and lisp (5, plus the stale compile-time comments
the review found in `lib/lisp/`).

## Batch A: bugs (parallel workers, disjoint files)

| Worker | Findings | Files |
| --- | --- | --- |
| driver | cache prune race; silent exit 134; worker-start report; script reuse with `-l`; `-v` command echo | src/utils.x, src/main.x, src/sourceview.x, src/collect/interfaces.x, src/translation.x, commands/build/** |
| protocol | handle participant operators; typedef participants in updates; update and discard helper linkage | src/expressions/operators.x, src/protocol/**, src/transform/operators.x, src/meta-group/** |
| generate | moved bodies and conditionals; inline bodies naming statics; projection of initialized globals; String switch helper linkage | src/generate/**, src/components/string-switch.x |
| regions | wide boxing and allocator rows; `move_to` rows; book guidance for containers | src/regions/**, docs/src/guide/{memory,regions,storage-ownership}.md, docs/library-api-tiers.txt |
| emit-macros | `sizeof` operand; rewrite first occurrence; holes in quoted data; `keyword` for Declaration macros; Symbol in a Type hole; `lisp.*` reservation | src/emit/**, src/macros/**, src/literals/** |
| parse | `auto try`; alias as enumerator; compound literal index; block declarators; C11 specifiers; Func field call; package surface default arm | src/parse/**, src/expressions/{access,calls}.x, src/collect/packages.x |
| callables | file-scope Func initializers; Iter chain arity; lambda adapter signature; `expand` hole kinds | src/transform/expressions.x, src/compiler/parsing/definitions.x, src/callables/**, src/components/macro-mapping.x |
| runtime-core | conversion boxing; `String.join`; constructor overflow; `find_within`; `exit(1)` floor; redundant guards | lib/common.x, lib/var/**, lib/string/**, lib/list/**, lib/array/**, lib/map/**, lib/exception.x, src/expressions/conversions.x |
| runtime-services | recursion limits on task stacks; regex brace repeat; HTTP HEAD; Lisp string escapes | lib/{regex,json,datum-reader,http,thread-state,task,thread}.x, lib/lisp/** |
| tests-scripts | skip inside a running test; fork output; `-fsigned-char` and build mode in probes, examples, benchmarks; `BUILD_JOBS` | unittest/test-support.x, unittest/test-{net,scope}.x, unittest/probes/**, unittest/benchmarks/*.sh, unittest/Makefile, examples/check.sh, examples/shootout/tools/shootout.py, Makefile (bm-*), etc/{build-config,x2c}.mk |
| docs | PR recipes; Logger guide; meta-function model; Var operators; CLI claims; symbols; stale names; package docs; module maps | docs/src/** (except the regions worker's pages), agents/**, AGENTS.md, README.md, packages/**/README.md, packages/AGENTS.md, src/**/README.md, etc/syntax/**, commands/test/** |

Each worker reproduces its findings from the review's probe programs,
repairs the cause, proves it with a fixture or unit test that fails before
and passes after, runs `make build` plus its focused checks (and
`make stage-1` for emission changes), and hands its commits to the
orchestrator. The orchestrator integrates the batch, reviews the combined
diff, runs the focused checks on the combined tree, and submits ready PRs.

## Batch B: contracts and waste (after batch A)

- Delete the REPL "loaded helper" chain (about 615 lines) and the three
  orphaned compiler methods.
- Delete `examples/shootout-unofficial/`; align the Notes benchmark
  reports with the compact-results policy that `dev` adopted on
  2026-11-01; move `commands/graph/clones-experiment.md` out of the tree.
- One owner for the package set (each package Makefile defines `check`);
  the released set stated once; release tooling reads it.
- One driver error reporter; stderr and JSON diagnostics name the same
  path; `TargetKind` owns product names.
- Operator ledger consumers in bracket-access, dynamic-operators, stage,
  and expressions read the ledger.
- Duplicate helpers in lib (pool copy, pthread abort, io-fail raise, UTF-8
  encoder, read-all, typed updates), src (`_never_defined`, `_inside`,
  `_valid_utf8`, import scanners), tests, tools, and CI steps.
- Guidance: the module map in one place; the code standard's restated
  rules removed from the philosophy, AGENTS.md, and the development guide;
  stale pre-release commit references; plans/README.md drift and the
  split plan name; the twelve reference records that still state holds.
- Stale derived artifacts: the packaged VS Code grammar and the viewer
  payload get an owner or leave the tree.

### Carried from the batch A handoffs

Defects the workers reproduced outside their files, for a later bug batch:

- A Func conversion nested in a file-scope collection literal runs before
  its handle (`static Array t = [(Func) twice];` holds a null Func); the
  fix belongs in `src/cache.x` `_visit`, which should take each deferred
  initializer's dependencies from the bindings its assignment reads.
- A protocol update helper named from a public inline body still fails in
  includers ("call to undeclared function"); its call names the helper by
  string, so the inline-static check does not see it.
- `$x2c.callback.adapt` adapters drop a `const` pointer result (`_split`,
  `_check_signature` in `src/callables/callbacks.x`); an inline lambda
  callback parameter type loses `const` through `resolve_key` in
  `_adapt_lambda_value`; nullary adapters are emitted unprototyped.
- `_check_arity` skips calls through a function pointer and
  `complete_iter_chain` completes only direct calls; consumers never
  complete chains at file scope, so a file-scope chain reports a wrong
  arity at an end-of-file position.
- The region check is silent on an implicit `List`, `Iter`, or typed-array
  conversion to `Array` returned from a region (a use-after-free under
  AddressSanitizer); producers without allocator rows: the base64 and hex
  `decode_bytes` readers, `ArrayT.array`, `Url.parse_query`, `Args.parse`,
  `SymbolSet.encode`, and the typed Array and Map families; operations that
  return their argument (`Array.reverse`, `sort*`, `setslice`, `Map.merge`,
  `Buffer.printf`) lose that aliasing.
- `_check_rebinding` misses a wrapped file-scope alias (`_same_scope` in
  `src/macros/aliases.x`); an alias does not conflict with a name an
  include delivers; a compound literal receiver is rejected as not
  addressable; `auto with = 5;` and `auto foreach = 5;` parse as regions.
- `Map.iter`, `keys`, and `enumerate` on a null Map raise `<bad-arg>`
  against the documented "exhausted"; `String.new_len` and `Buffer.str`
  accept a length of `INT_MAX` and overflow in `_store`; `Regex.compile`
  recursion is unbounded (100,000 nested groups crash); the Lisp evaluator
  checks the stack only at lambda calls and overflows a 32 KiB task under
  AddressSanitizer.
- `$fail.frontend_input_read` always says "cannot open"; `-v` and `-###`
  translate lines are not shell-quoted (`_print_action` in
  `src/toolchain.x`); a cache record or depfile with a NUL byte ends in an
  uncaught `<bad-arg>`; `x2c script` on a file without the shebang reports
  a parse error instead of the missing shebang.

Waste and drift the workers saw, for this batch:

- `_switch_in_public_inline` and `_string_switch_public_role` repeat
  `_lambda_in_public_inline` and `_lambda_bridge_role`; the "runtime
  source" test lives in `src/collect/walk.x`, `src/frontend.x`, and
  `src/macros/definitions/reading.x`;
  `$fail.expressions_operand_unconverted` belongs beside its sibling in
  `src/expressions-reports.x`; `_search_link` in `src/meta-project.x`
  rebuilds meta helpers for every `-l`; `lib/channel.x` still boxes through
  `convert(<long>)`; `protocol_helpers` cache entries may survive a
  semantic-transaction rollback (unverified).
- `x2c test` takes `--manifest` while `build`, `run`, and `repl` take
  `--manifest-path`; `JOBS` survives in `unittest/compiler-fixtures/
  README.md`, `tools/test-examples.py`, `tools/gate-state.py`, and the
  beautify coverage probe; `examples/Makefile` includes neither `.mk`;
  `unittest/benchmarks/hash-table/run.py` compiles without
  `-fsigned-char`; `examples/shootout-unofficial` reads only the tracked
  mode file; `tools/check-generated-stages.sh` stops at the first
  differing file; `make verify` does not depend on `commands`, yet its
  CLI probes make the driver check `x2c-package`, so a compiler rebuild
  without `make commands` fails them with an identity mismatch.
- Book: body placement before a later `#define` or `#include` and the
  public-inline rule in `language.md`; `^` declarators still shown in
  `x2c-syntax-map.md`, `etc/syntax/grammar.x`, and `extensions.x`, which
  also omit `_Alignas`, `_Atomic`, and `_Complex`; `language.md` keyword
  alias kinds omit Declaration, `$lock` is redefinable against the text
  near line 2857, and the escape spans near line 3363 render with two
  backslashes; `expand` is reserved in expressions but unlisted; a
  `foreach` variable typed by a struct tag escapes the Var conversion
  check; `cli.md` script-reuse triggers omit `-l`; `packages/pcre2/
  README.md` shows `defer` where the `auto` form is now described;
  `unittest/AGENTS.md` and `STATUS.md` need the skip-inside-a-test rule.

### Carried from the batch C handoffs

Defects and drift the batch C workers reproduced or read outside their
items, for a later batch:

- `Logger.new` returns NULL for an invalid level, so the NULL now fails at
  its first use instead of the constructor raising (ER-1).
- `Lisp.call_budget` ignores a nonpositive budget silently although its
  doc says the budget must be positive; the `Lisp.bind` doc omits the
  `<bad-state>` a frozen session raises after the `Func` has moved;
  `Lisp.try_get` and `Lisp.read` document their own null-session
  behaviour, outside the handle rule.
- `lisp_source_function`, `Lisp.automatic_storage`, and
  `Lisp.result_storage` have no callers outside `lib/lisp` and its test:
  candidates for deletion.
- `Array.take_last`, `shift`, and `remove` return `void` on a null array or
  an index outside the elements (the decision covered writes only);
  `Array.getindex` dereferences a null array under its documented
  non-null precondition.
- `Iter.parallel_map` and `parallel_map_in` take a `ThreadValueFn`; their
  null-function behaviour was not checked.
- `lib/channel.x` uses an `argument` detail key that DG-7 does not list;
  `Listener.write_repr` formats a null handle's text.
- Not audited for null-handle sites: `lib/match`, `lib/dispatch.x`,
  `lib/static-init.x`, `lib/var`, `lib/pool`.
- Lines over 79 columns that predate the batch: `lib/lisp/lisp.x` (five,
  deliberate one-line error macros) and `lib/process.x` (three) from the
  compact-diagnostics commit, `unittest/test-lisp.x`, `test-iter.x`,
  `docs/src/guide/iteration.md`, and `collections.md`; translating
  `test-lisp.x` reports four unnecessary `.str()` conversions.

## Validation and delivery

Workers: focused checks only. Orchestrator: combined focused checks and
`make stage-1` on the integrated batch, lint census on changed entry
units, `git diff --check`. The integrator owns the publication gate and
`dev`.
