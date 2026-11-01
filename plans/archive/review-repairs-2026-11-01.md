# Repairs and mitigations at the margins of the October 31 rounds

> Status: done - all five batches published to `dev` on 2026-11-01;
> batch E closes the plan at `b77c7a44a`. Recorded 2026-11-01 against `dev`
> `f12c7619a`. A6 moves to F10 of the follow-ups.
> Source: a read-only review of the grouped Map, execution-stack,
> macro-decorator, and repair-wave rounds (`9c8fbbe8b` through `f12c7619a`).
> Batch A (compiler defects A1-A5) is published to `dev` at `e1b2bacbb`;
> see its delivery record below. Batch B is delivered in `147ce79ee`,
> batch C in `0de444adf`, batch D in `eb8b27496`, and batch E in `b77c7a44a`.
> Batch A also absorbs follow-up F4 from the
> [October 31 follow-ups](../review-followups-2026-10-31.md).

## Review scope and baseline

The review read every authored change in the four rounds, compared it with
the book, agent guides, plans, benchmark records, tests and fixtures, and
reproduced the behavioral claims with probe programs against `builds/0` at
`1f32c57e2`. On that revision `make verify` passes with 1,164 tests and
103,725 assertions, and the llms, syntax-spec, module-catalog, API-reference
and documentation-audit checks all report current. The nine shootout commits
that followed touch only `examples/shootout/` and one archived plan.

Verified clean, and not repeated below: HEAD equals `origin/dev` and the
bootstrap follows the last source change; no public runtime signature changed
in `lib/map`, `lib/pool`, `lib/task.x`, `lib/channel.x` or the typed map
files; the split side-hash storage carries its `Block.lifetime` on every
growth, cleanup, export, move, free and root-growth path; the probe-cache
revert `27c6e079d` is complete; `expand` has one lexical treatment across the
scanner, tokenizer, book, EBNF and editor grammar, and the `macro-expand`
fixture builds under `--cpp`; all six repair-wave repairs exist with committed
fixtures and no second copy; every plan, `SUMMARY.md`, manifest and tier link
resolves. Not examined: Linux/GCC and x86 scalar behavior at runtime,
generated bootstrap C beyond greps, the site build, the torch package's
`Tensor.expand` method, and any performance claim.

## Batch A: compiler defects

Use `fix-x2c-bug`. Each repair starts from its reproduction.

| ID | Defect and reproduction | Owner and repair | Evidence |
| --- | --- | --- | --- |
| A1 | A named Macro target consumed by `expand` stays published. `expand %(1 2) macro Stmt $add(Expr $n) { total += $n; }` followed by `$add(5);` compiles and prints 8. The decorator plan says the original definition must not become visible after mapping consumes it. | `Compiler.publish_macro_definition_node` (`src/macros/invocations/recognition.x`) writes `c.macros[name]` directly, so the always-rolled-back capture transaction in `_macro_argument` (`src/macros/invocations/captures.x`) cannot withdraw it; local named definitions go through the symbol table and are withdrawn. Route the global publication through the transaction-tracked write that `_tracks` (`src/symtab/transactions.x`) already undoes, or publish a captured named definition only from the decorator producer's named branch. Keep the provisional self binding inside the body. | New negative fixture `macro-expand-consumed-target`: the later `$add(5)` reports an unknown macro at its own location. Extend `macro-expand.x` with a named generator whose body calls itself, proving the self binding survives. |
| A2 | Inside a template, `expand` of a meta-produced List needs an internal wrapper. `expand $_rows($fields)` in a `macro Stmt` fails with `syntax cannot be constructed at this position`; the same template with `$_x2c_literal_list($_rows($fields))` works. The book says only that the expression must produce a compile-time List, and `docs/library-manifest.txt` marks `lib/compiler-meta.x` internal. The adoption in `src/fields.x` and `lib/native-scalar-types.x` depends on the wrapper. | `_x2c_expand_rows` (`src/components/macro-mapping.x`) resolves `input` as an expression before `Code.value`. Evaluate a meta-call input the way `_producer_value` (`src/macros/expansion.x`) evaluates a meta-call producer, through the existing meta evaluation, so a template input needs no literal wrapper. Then remove `$_x2c_literal_list` from the two adoption sites. If the decision is instead to require a spelling, give it a documented public name; do not leave the internal wrapper as the only working form. | New fixture `macro-expand-template-rows`: a user `meta` helper feeding `expand` inside a `macro Stmt` with a `Name @fields` hole, run and checked. The existing `field-copy-set` fixture and `make stage-2` cover the adoption sites. |
| A3 | An attribute macro before `typedef` drops the attribute. With `#define AL16 __attribute__((aligned(16)))`, `AL16 typedef int Written;` gives `alignof` 4 while `__attribute__((aligned(16))) typedef int Spelled;` gives 16. Under `--cpp` both give 16 because the macro is expanded first. This is the written/macro asymmetry behind follow-up F4. | `_attribute_macro` (`src/parse/types.x`) exits when the next token is `typedef`, and its comment says a typedef keeps no leading text; `d31307a59` made that false because `_typedef` (`src/parse/declarations.x`) now keeps `%(@text @spec)`. Keep the macro name as leading text on the typedef path exactly as the written attribute is kept, and correct the comment. Close F4 against this repair, or narrow F4 to the included-header case it still describes. | Extend `leading-attribute-typedef` with the `#define` form and expect `16`. Rerun `cpp-quoted-keyword-atoms` and the attribute-macro declaration fixtures. |
| A4 | Mapping diagnostics name internal generators. `macro-expand-missing-target.diagnostics` says `decorator '_x2c_gensym_anonymous_macro_0' requires a following target`; `macro-expand-position` and `macro-decorator-continuation-position` are similar, and arity notes cite `etc/compiler-prelude.x:81:3`. The committed expectations lock this wording in. | The macro diagnostic owners in `src/macros/diagnostics.x` already carry the invocation site. Name the keyword alias or "the anonymous generator" in the primary message instead of the generated spelling; keep the located input note. A mitigation, not a behavior change. | Refresh the three `.diagnostics` expectations through `make verify-fixtures-update` and review each diff. |

| A5 | Stacked Macro-target decorators over a named definition fail. `$keep() $keep() macro Decorator $guard(Stmt $body) { ... }` reports `syntax cannot be constructed at this position` at file scope. The book promises closest-first stacking. Found while adding the stacking coverage below. | `_decorate_producer` (`src/macros/invocations/targets.x`) decided publication from the source at the target start, so an inner decoration parsed in expression position tried to bind a named definition there. Decide from the result instead: a named definition is published, in expression position as a Macro value for the enclosing target; an anonymous Decorator continues. The anonymous-name test lives once in `Diagnostics.anonymous_macro_name` (`src/diagnostics.x`), which the unit-test link can carry without further compiler objects. | `macro-decorator-continuation` gains two tallying Macro-target decorators that record their order at file scope. |
| A6 | A Macro-target decorator over a local definition leaves that local invisible. In a function, `$keep() macro Decorator guard(Stmt $body) { ... }` followed by `guard() { ... }` reports `expected atomic expression` at the call, with one decorator or two, on the seed compiler as well as the repaired one. Not repaired in this batch. | The returned local definition reaches `_bind_macrodef` (`src/parse/units.x`) through `bind_syntax`; trace why the published local name is not found by the bare-name invocation, then decide whether the book's "a macro may generate a local definition" covers decorators. | Add the function-scope case to `macro-decorator-continuation` when repaired. |

Coverage the decorator plan named but did not land, added with A1, A2 and A5:
the row-failure fixture `macro-expand-row-failure` and the closest-first
stacking checks above. Observed while adding them, and left as recorded
behavior: a file-scope decoration runs once in collection and once in
parsing, so a meta helper with side effects sees each file-scope form twice;
block-scope forms run once. The fixture checks only the first recorded pair.

### Batch A delivery, 2026-11-01

Implemented in `33711ac94` (A1-A4 and their fixtures), the bootstrap
refresh `f59e16161`, `89908c3a9` (A5 and the adoption that drops
`$_x2c_literal_list` from `src/fields.x` and `lib/native-scalar-types.x`),
`800082e80` and `153175515` (the anonymous-name test kept inside
`src/diagnostics.x`, which the unit-test link carries, with the final
bootstrap and generated pages). A6 is recorded, not repaired.

`tools/gate-state.py ensure agent-pr-check` passes on the completed tree:
1,164 unit tests with 103,725 assertions, 1,383 compiler fixtures with 3,052
artifacts, 138 book samples with matching output, cold collection, command
checks, and the self-host comparisons. Fixture changes: three new fixtures
(`macro-expand-consumed-target`, `macro-expand-template-rows`,
`macro-expand-row-failure`), the extended `leading-attribute-typedef` and
`macro-decorator-continuation`, eight diagnostics expectations that now name
`expand` or `$unit` instead of a generated spelling, and `c-prefix-macros`,
whose typedef now keeps its attribute macro in the C and the header like a
written attribute. No public runtime signature changed. The D3 allocation
microbenchmarks were not run; batch A touches no allocation path.

## Batch B: release notes and distribution

| ID | Gap | Repair |
| --- | --- | --- |
| B1 | `docs/src/reference/release-notes.md` (Unreleased) has no entry for the `%<<a>>` to `%<a>` SymbolSet literal change (`37e0d8a2b`), which the v0.15.1 book used in five chapters, and the installation upgrade table has no row for it. Also missing: contextual x2c keywords, macro-target decorators and `expand`, grouped and split Map storage, the experimental `x2c bind` command, and the three repair-wave fixes (leading typedef attributes, quoted keyword atoms under `--cpp`, the generated-owner protocol diagnostic). | Add the entries under the existing Language, Library, Commands and Fixed headings, with a breaking-change upgrade row for `%<...>` in `docs/src/guide/installation.md`. Each entry links its book section. |
| B2 | `lib/task/minicoro.h` (minicoro v0.2.0, Unlicense or MIT-0) is compiled into `libx2c.a` through `builds/stage.mk`, yet `THIRD_PARTY.md`, `NOTICE` and `LICENSES/` do not mention it, and `site/src/content/home.md` still says the compiler, library and runtime have no third-party library dependencies. | Add a vendored-runtime-sources section to `THIRD_PARTY.md` naming minicoro with the pinned revision, digest and license from `lib/task/README.md`, put its license text under `LICENSES/` beside the linenoise text, and qualify the home-page sentence. |
| B3 | The payload row `("builds/0/lib" ("*.h") ("include/x2c"))` in `etc/x2c-payload.x` installs the patched `minicoro.h` into the public include directory. No generated header includes it; only `task-native.c` does. | Exclude native-private headers from that row, or copy them to a private directory. Confirm with `tar tzf` on a staged payload that `include/x2c/minicoro.h` is absent and `group-match.h` is still present, since generated C includes the latter. |

### Batch B delivery, 2026-11-01

Delivered in `147ce79ee`. The release notes gain the `%<a b>` literal, the
contextual keywords, Macro-target decorators with `expand`, the shared
grouped Map storage with its traversal-order note, the experimental
`x2c bind` command, and three fixed defects; the attribute-macro entry now
covers typedefs. The installation upgrade table gains rows for `%<<a b>>`
and for an object or function named `expand`, with a probe confirming that
a `Type.expand` method still compiles. `THIRD_PARTY.md` gains a vendored
runtime sources section for minicoro and its LuaCoco-derived assembly, with
the license text under `LICENSES/`, and the home page qualifies its
dependency claim. `etc/x2c-payload.x` skips `minicoro.h`; a scratch
`make install` ships `group-match.h`, `x2c.h`, and the three license files
and no `minicoro.h`. The documentation audit passes with the new links.

## Batch C: grouped Map margins

Code items first, then prose. None changes behavior.

| ID | Drift | Repair |
| --- | --- | --- |
| C1 | `lib/map/generics.x`: the comment `Native updates share lookup and insertion; Var updates belong to Map.` now sits above `$map.core.observe`; `$reinsert_error` keeps an `int probe` parameter whose only caller passes 0 (it was the Robin Hood probe length). | Delete the comment. Drop the parameter and the `(probe ...)` cause field in `generics.x`, `grouped.x`, and the `map-generator-family` fixture signature. |
| C2 | The stated reason for nonzero hashes is stale: `lib/dispatch.x` (`_nonzero`) says Map stores a nonzero hash beside each record and `lib/common.x` says zero marks an empty bucket. Grouped tables mark occupancy in control bytes; the only remaining zero-as-empty consumer is `lib/pool/root-index.x`. `258290d23` deleted the `map.x` note that recorded the obligation, and `lib/typed-map.x` calls its normalization "production's zero normalization". | Point both comments and the typed-map wording at the root index as the owner of the reserved value, and restore a one-line note at the root index. |
| C3 | `lib/map/grouped.x` header names two hash policies (cached in the record, recomputed) and omits the side-hash policy Map and Pool use; `lib/map/map.x` says a record and its cached full hash occupy the same bucket, but `MapRecord` has no hash field. | Describe the three policies once in `grouped.x` and correct the `map.x` bucket comment. |
| C4 | Agent guides still name `lib/map/generics.x` as a Robin Hood owner: `agents/x2c-philosophy.md` (exemplars), `agents/adapters-macros-decorators.md` ("a second Robin Hood table", `generics.x` as storage owner, direct `Scope_malloc`/`Bytes` calls), and `agents/x2c-code-organization-guide.md` (omits `map/grouped.x`). `unittest/benchmarks/hash-table/README.md` still calls `x2c/u32-map.x` an extraction of the production Robin Hood layout, and the README and `direct/run.sh` record only `lib/map/map.x` as source provenance although the timed probe code is in `grouped.x`. | Point every guide at `lib/map/grouped.x` as the storage owner with `generics.x` as the family operations owner; call U32Map a retained Robin Hood specimen; add `grouped.x` and `generics.x` to the provenance rows. |
| C5 | `unittest/test-map.x` `map_collision_backshift_and_reuse` and `unittest/test-typed-map.x` `typed_map_growth_collision_backshift_and_reuse` select keys by `hash & 7` at capacity 8, which is one group under grouped storage; they now test tombstone reuse. Threshold coverage crosses 65536 buckets only through implicit counts (50,000 entries in `test-context.x` and `test-storage-ownership.x`, 32,768 in `test-pool.x`). | Rename the two tests for tombstone reuse or select keys by grouped fingerprint as `test-typed-map.x` already does elsewhere. Assert `capacity >= 65536` where a test means to cross the split threshold, so moving the threshold cannot silently drop coverage. |
| C6 | `docs/src/guide/collections.md` says large tables allocate hashes "under the controls Block's storage owner"; the code allocates them in the Block's owned lifetime scope. | Say "in the controls Block's owned storage", matching `map.x` and `pool.x`. |
| C7 | Records state superseded facts without a pointer: `plans/archive/grouped-typed-map-adoption.md` ("Var Map and Pool retain their Robin Hood storage") and `plans/archive/retire-robin-hood-map.md` (full hashes always inside the controls Block). The split report says probing and prefetch policy are unchanged but not that it re-adopted the hash-pointer cache from the reverted experiment without the per-index prefetch, and its baseline for identical storage code (94.5 ns Var counting) differs from the retirement report's 83.7 ns without comment. | Add one dated "superseded by" line to each archived status blockquote. Add one dated paragraph to `grouped-split-adoption-20261101.md` stating which half of the reverted experiment the split change adopts and that the two campaigns' absolute baselines are separate runs. |

Mitigation recorded, not scheduled: the control-byte format (128 empty, 254
deleted, 16-lane groups, `>> 25` fingerprints) is restated by `_get_string`
in `lib/pool/interning.x`, `MapStringInt.add_substr` in `lib/typed-map.x`,
and `_prepare_export` in `lib/substring-map.x`. They agree today. Record the
coupling at the format's owner in `grouped.x` now; consolidate into one
shared probe only when a format change is selected, since the copies exist
for allocation-free byte and substring paths.

### Batch C delivery, 2026-11-01

Delivered in `0de444adf`. `$reinsert_error` loses its `probe` parameter in the
generator, the two generator fixtures, and the invariant cause; the orphaned
comment is replaced. The nonzero-hash rationale in `lib/dispatch.x`,
`lib/common.x`, and `lib/typed-map.x` now names the root Pool index, which
states the reserved value in its header. `grouped.x` describes its three
hash policies and `map.x` its record. The philosophy exemplars, the adapter
guide, the organization guide, the benchmark README, and the direct runner's
provenance name `grouped.x`. The two tombstone-reuse tests are renamed, and
the threshold tests assert `capacity >= 65536`. The book says "owned
storage", the two archived plans carry superseded-by lines, and the split
report reconciles the pointer cache with the reverted experiment. `make
verify` passes with 1,164 tests and 103,728 assertions and 1,383 fixtures;
no fixture artifact changed. The probe-copy consolidation stays deferred.

## Batch D: execution-stack margins

| ID | Drift | Repair |
| --- | --- | --- |
| D1 | Public Scope prose still says retain/release for operations now named `Scope.open`/`Scope.close`: `lib/scope/regions.x` (region comments and the destroy comment), `lib/scope/allocation.x`, `lib/scope/runtime.x`, `lib/scope/scope.x`, and `docs/src/guide/memory.md`. These reach the generated `docs/src/library/modules/scope.md`. | Reword the public prose with open/close; private names such as `_record_retain` and `retains` stay. Regenerate with `make doc-generate`. |
| D2 | `agents/x2c-philosophy.md` still states the withdrawn contract that `Scope.destroy` accepts only a detached root and rejects attached lower scopes; `regions.x` now says destroy rejects the execution base and pushed slots and does not diagnose every invalid destruction. `agents/x2c-code-organization-guide.md` omits `task.x` from the runtime row. [packages/torch/benchmarks/PILOT.md](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/packages/torch/benchmarks/PILOT.md) uses `Scope.retain`/`Scope.release`. `examples/apps/notes/bench/README.md` still says the in-process probe requires the local async prototype. | Restate the destroy paragraph as the caller lifetime contract; add `task.x`; rename the PILOT reproducer; drop the prototype sentence. |
| D3 | Two owners validate task stack bounds: `lib/task.x` `_stack_size` rejects below 32768 or above `SIZE_MAX - 65536` and raises `bad-arg`; `lib/task/stack.c` `x2c_task_stack_new` rejects below `MCO_MIN_STACK_SIZE` or above `SIZE_MAX - 2 * page` with `EINVAL`. `_thread()` in `regions.x` has two lazy-init tests for fields that are always set together, and `lib/scope/runtime.x` reassigns `active` right after `_thread()` set it. `lib/channel.x` re-tests `task` around `x2c_task_stopping`, which already returns `job && ...`. | Let `task.x` own the bounds and have `stack.c` trust its only caller, keeping the `bad-arg` cause. Set `base_slot` and `active` under one `!active` test and drop the redundant reassignment. Drop one side of the channel null test. |
| D4 | The nested-batch rejection in `Task.run` (`nested task batches are unsupported`) is documented but untested. The optional backend probe `unittest/probes/run-task-backend.sh`, `task-unsupported.x` and `lib/task/README.md` call the unsupported-target branch a "fallback", which the plan rules out. | Add one assertion to an existing `test-task.x` test. Rename "fallback" to "unsupported target" in those headers. |

### Batch D delivery, 2026-11-01

Delivered in `eb8b27496`. The public Scope prose in `lib/scope/*.x`,
`lib/context.x`, `docs/src/guide/memory.md`, and `system-macros.md` says
open and close; `make doc-generate` carried it into `scope.md` and
`context.md`. The philosophy states the destroy contract as the caller's
lifetime obligation, the organization guide lists `task.x`, the PILOT
reproducer uses `Scope.open`/`Scope.close`, and the Notes bench README no
longer names the prototype. `lib/task.x` is the only owner of the stack
bounds; `stack.c` trusts it, and the layout probe drops its two `EINVAL`
assertions. `_thread()` installs both slots under one test, `_initialize`
no longer reassigns `active`, and `channel.x` relies on
`x2c_task_stopping` accepting NULL. The empty-batch test asserts the
nested-batch `bad-state`, and the optional backend probes say
"unsupported target". `make verify` passes with 1,164 tests, 103,729
assertions and 1,383 fixtures; `run-task-backend.sh` passes; check-docs
passes. Retired-instruction medians of five alternating runs, `-O2`, before
and after: 100,000 regions destroying 16 allocations 1,838.9 M to 1,833.8 M
(-0.28%); 1 million malloc/realloc/free cycles 1,830.7 M to 1,829.6 M
(-0.06%); the Scope hot-path benchmark 2,514.7 M to 2,508.1 M (-0.26%).
All three are within the noise floor.

## Batch E: plan and record hygiene

| ID | Drift | Repair |
| --- | --- | --- |
| E1 | `plans/reference/async-task-prototype-2026-10-30.md` and `async-validation-2026-10-31.md` open with plain status text saying no push or dev/main integration is authorized and the hold remains; `async-channel-runtime-spike-2026-10-30.md` has a design-succession blockquote and no status line; `async-numeric-fixes-2026-10-31.md` carries the same hold wording inside its blockquote. The work was published as `255de641f`. | Give each a `> Status: reference` blockquote dated 2026-11-01 that records publication at `255de641f` and marks the hold text historical. |
| E2 | Nine `plans/reference/async-*.md` records cite evidence under `.context/`, which `.gitignore` excludes, so the cited files cannot be recovered from the repository. | State in each citation that the evidence is workspace-local, and move any excerpt the record relies on into the record. |
| E3 | `plans/archive/recent-wave-repairs-2026-10-31.md` names `src/parse/types.x` as the typedef repair owner; the second half of that repair is `_without_leading_text` in `src/type.x`. `plans/README.md` lists 122 of 214 archived plans and 10 of 28 reference records without saying the listing is selective; fourteen plans archived since 2026-10-22 and all eleven async records are unlisted. | Correct the owner. Add one sentence to the README saying the completed-records list is selective, and list the records archived since 2026-10-22. |
| E4 | Follow-up F4 in `review-followups-2026-10-31.md` describes the included-header attribute-macro case; A3 reproduces the adjacent written-source case. | When A3 lands, close F4 or narrow its row to the remaining included-header symptom. |

### Batch E delivery, 2026-11-01

Delivered in `b77c7a44a`, documentation only. The prototype, validation,
spike, and numeric-fix records carry `> Status: reference` lines dated
2026-11-01 that record publication at `255de641f` and mark their hold text
historical. The twelve `.context/` citations in nine async records say the
evidence is workspace-local and untracked; the integration record states
that its revisions are already in the text, and the numeric record that its
failure counts are. The recent-wave archive names `_without_leading_text` in
`src/type.x` beside the parser owners. The README says its completed list
is selective, lists the fourteen plans archived since 2026-10-22 and the
async evidence family, and drops this plan from active work. F4 was narrowed
to the included-header case when A3 landed, and A6 becomes follow-up F10.
This plan moves to `archive/` with the batch.

## Delivery and validation

Delivery follows the root `AGENTS.md`: direct to `dev` unless Gary selects
the shared integrator or a review stop. Two coherent batches:

1. **Code batch:** A1-A4, B3, C1, C2 (comments only), C5, D3, D4. Review the
   combined authored diff first. Focused checks: the new and extended
   fixtures above, `unittest/test-map.x`, `test-typed-map.x`, `test-pool.x`,
   `test-context.x`, `test-task.x`, `test-channel.x`, and `make stage-2`
   because the adoption sites in `src/fields.x` and
   `lib/native-scalar-types.x` change. Then
   `tools/gate-state.py ensure agent-pr-check` once on the integrated tree.
   D3 touches the Scope allocation path; rerun the region and
   malloc/realloc/free microbenchmarks recorded in
   `plans/reference/async-validation-2026-10-31.md` before and after, and
   record the instruction counts. No other item is hot-path work.
2. **Documentation batch:** B1, B2, C3, C4, C6, C7, D1, D2, E1-E4. D1
   regenerates `docs/src/library/modules/scope.md` through `make doc-generate`.
   Validate with `tools/gate-state.py ensure doc-check`. If the two batches
   land together, the code gate covers both.

Commit subjects stay short, lower-case and present tense. No new recurring
gate, test target or process step is added. The three new fixtures and one
assertion are focused regression coverage under the existing harness.

## Plan review

- **Established facts.** The semantic transaction owns withdrawal of every
  binding written through the symbol table; A1 makes the global macro
  publication use that owner instead of adding a second rollback. Ordinary
  meta evaluation owns compile-time values; A2 reuses it in the mapping
  helper rather than keeping a second spelling. `_typedef` owns leading text
  for typedefs; A3 feeds it the macro name instead of a parallel path. The
  root index owns the reserved zero hash; C2 names that owner. `Task.run`
  owns capacity validation; D3 removes the duplicate in `stack.c`.
- **Deleted or reused.** C1 deletes an orphaned parameter and comment. D3
  deletes a duplicated bound, a redundant lazy-init branch, an assignment,
  and a null test. A2 deletes the wrapper from two adoption sites. No new
  helper, representation, traversal, cache or state is introduced; the
  probe-copy consolidation is deliberately deferred.
- **Idiomatic x2c.** Every repair edits the existing owner in place, keeps
  Match-based recognition and ordinary binding, and adds no framework,
  origin check or compatibility shim.
- **Validators, diagnostics and negative fixtures.** One negative fixture
  (A1) protects the documented rule that a consumed named generator is not
  visible afterward. A4 rewords existing diagnostics without adding one.
  The nested-batch assertion (D4) covers an existing `bad-state` raise. The
  threshold assertions (C5) protect the split-storage path from silently
  losing coverage. No new validator or dedicated diagnostic is proposed.
