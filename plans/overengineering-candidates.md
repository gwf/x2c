> Status: reference
>
> This is the compact collaborative ledger for cumulative `src/` and `lib/`
> overengineering forensics. Detailed and empty run evidence stays outside Git
> under `~/.codex/x2c-overengineering/`. A row is a review lead or disposition,
> not authorization to remove code.

# Overengineering candidates

## Live candidates

| Candidate | Location | Machinery | Claimed purpose | Production consumers | Overreach evidence | Removal hypothesis | Strongest keep case | Provenance | Status / confidence | Next proof |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `compiler-packing-simulation` | `src/compiler.x:615-775,786-805,815-822,827,847-854`; packing portion of `_scan_conditionals` | Parallel pack readings, pack stack simulation, layout-macro registry, and `pack_marks`; digest `1831e6f3` | Prevent compile-time natural layouts for packed records and range inference for packed enums | `src/parse.x:_packed_since` and `_publish_aggregate_type` consume the marks; `Compiler.tokenize` produces them | The narrow refusal rule expanded through five rapid commits into conditional simulation and macro propagation, while the plan still records incomplete forms | Keep ordinary conditional tracking; replace only packing simulation with one conservative layout-unsafe fact at collection/type ownership | Current machinery prevents demonstrably wrong compile-time layouts; no existing smaller path has yet been shown to preserve that safety | Conditional owner `897a30f8`; packing cascade `299fffca`, `9ca8152c`, `9e38670b`, `778b13c4`, `272bbb49` | `open` / high suspicion, unproved removal | Prototype or trace one conservative decline bit and show packed fixtures still decline while plain records retain layouts |
| `match-admission-memos` | `lib/match.x:2017,2032,2043-2048,2067-2081` within `_cache_admitted`; digest `6a331819` | Two 256-entry admitted/refused memo arrays and slot folding | Avoid recursively rechecking whether repeated patterns may be borrowed by the plan cache | `_cache_admitted`, called by `MatchCache.acquire`; the admission gate itself is required | Small derived cache inside a larger cache; mechanical scan cannot establish whether its saved work earns its state | Retain epoch resync and admission correctness, but call `_cache_keyable` directly instead of memoizing admission | `90685897` attributes material translation regression partly to repeated rewalk/refusal; removing the memos may restore that cost | Cache restoration `712bcb73`; epoch/admission repair `90685897` | `open` / medium-low | Isolated A/B benchmark of source translation and repeated dynamic-pattern workloads with only the admission memos removed |
| `macro-import-function` | `src/macros.x:_import`, lines 1352-1509; digest `614c793d` | Import canonicalization, cycle stack, cache replay, macro/meta merge, dependency and declaration effects | Implement `.xmacro`/`.xlisp` imports across compiler passes | Parser hook, Lisp hook, macro lookup, frontend dependency/cache, declaration-effect queues, and emitted meta forms | Large and historically repaired, but the whole-function hit conflated several distinct documented obligations | None supported for the whole function; cached replay may be investigated separately only with binding and performance evidence | It is a live public language feature with explicit identity, cycle, ordering, and per-unit semantics | Initial source `4235c383`; binding replay `dce252e1`; meta import `3f104236` | `rejected` / medium-high | No whole-function follow-up; create a narrower replay candidate only if a concrete duplicate owner is found |
| `match-cache-resync` | `lib/match.x:_cache_resync`, lines 2050-2065; digest `225cc8c0` | Epoch check and retirement of unpinned borrowed-identity plans | Prevent recycled Pool addresses from validating stale cached plans | `_cache_admitted` calls it before cache lookup; active leases force the transient path | Mechanical cache/state signals only; source review found a distinct correctness owner | No smaller existing path; alternatives retain/copy constants or recreate the cache on pool close and are larger | Direct address-reuse coverage plus measured translation and repeated-pattern performance | Introduced by `90685897` after the permanent-only policy regressed translation | `rejected` / high | None unless Pool identity or cache ownership changes |
| `comptime-switch-lowering` | `src/comptime.x:_lower_switch`, lines 1771-1861; digest `42f31eda` | Subject-once lowering, grouped labels, continuation handling, environments, and fallthrough refusal | Support ordinary `switch` in compile-time x2c | `_lower_stmnt` dispatches to it; compiler fixtures exercise supported and declined forms | Mechanical size and route signals only; design deliberately refused the state-machine alternative | Removing it would make compile-time functions containing switch decline | It owns distinct current language behavior and already uses the bounded design | Phase 2 control-flow commit `b9f54a28` | `rejected` / high | None unless compile-time switch support is intentionally withdrawn |

## Calibration cases

These historical cases calibrate discovery. Removed code is never returned to
the live queue.

| Case | Historical region | Outcome | Evidence and use |
| --- | --- | --- | --- |
| Packed-layout detection and replay | `src/compiler.x`, `src/collect.x`; packing state, conditional scan, include replay in `d113f866` through `7815096c` | Positive; removed by `2334d78c` | A narrow refusal rule expanded into exhaustive detection and replay. Deleted parent-side blame leads to ten campaign commits. |
| Unsupported stabilization scope | `src/comptime.x`, `src/parse.x`, and related state in `f1228d90`, `08edced1`, `b6d79c71`, and follow-ups | Positive; removed by `30615669` | Same-day public-definition, typed-call, local-static, callback, and effect machinery was stripped from the supported candidate. |
| Var tag ledger port | `lib/var-tags.xmacro`, `lib/common.x`, `src/compiler.x` in `20f8ac13` | Positive; reverted by `422b8cae` | 437 of 443 removed authored lines came from the same-day port; measured translation cost forced reversal. |
| Initial region analysis | `src/regions.x`, `_unwrap` through `Compiler.check_regions`, in `ac931c4a` | Positive churn signal; rewritten by `d3a61995` | 961 of 999 replaced lines came from the previous day's initial implementation. Use as a representation-first warning, not proof that region warnings are unnecessary. |
| Cleanup/emitter leftovers | `src/cleanup.x` and `src/emit.x` helpers introduced by `68eea0ae` | Positive but weak; reduced by `cecdf222` | Recent pass machinery left helpers and emitter paths that quickly became unnecessary. |
| Iterator combinator family | `lib/iter.x` removed by `50dec555` | Negative; restored by `2b3a7ba1` | Deletion did not prove overengineering; the project deliberately restored the behavior. |
| Error record accumulation | `lib/error.x` removed by `581f62f4` | Negative; restored by `b0af619f` | Treat as a false-positive control for aggressive deletion campaigns. |
| Source-map and dependency options | compiler and CLI paths removed by `1592f244` | Negative/mixed; partly restored by `08e03ca7` | Low use and recent origin were insufficient evidence that the surface was unnecessary. |
| Open public APIs | Any current non-static library operation with no in-tree caller | Negative by rule | Future external use is legitimate; absence of repository consumers cannot make a public API a candidate. |

## Ledger rules

- Statuses are `open`, `confirmed`, `rejected`, `superseded`, and `removed`.
- Record current lines and a region source digest when reviewing a live row.
- Reinspect a row when its digest changes; do not carry its verdict forward.
- Keep mechanical hits and empty searches in the external run, not this table.
- A confirmed row still requires separate authorization before deletion.
