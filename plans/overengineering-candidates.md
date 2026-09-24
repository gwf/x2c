> Status: reference
>
> This is the compact collaborative ledger for cumulative `src/` and `lib/`
> overengineering forensics. Detailed and empty run evidence stays outside Git
> under `~/.codex/x2c-overengineering/`. The live table contains only internal
> abstractions whose removal is expected to preserve intended behavior. A row
> is not authorization to remove code.

# Overengineering candidates

## Live candidates

| Candidate | Location | Machinery | Claimed purpose | Production consumers | Overreach evidence | Removal hypothesis | Strongest keep case | Provenance | Status / confidence | Next proof |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

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
| Dynamic typed `Func` calls during compilation | `src/comptime.x:_lower_application` and its carrier bridge | Negative by rule and explicit decision | This is wanted higher-order compile-time behavior. Its implementation size and lack of an in-tree adopter do not make it a candidate. |
| Match admission memos | `lib/match.x:2017,2032,2043-2048,2059-2061,2072-2079` | Negative; rejected after isolated A/B | The 4 KiB derived memo state owns no semantics, but bypassing only its lookup and writes made literal matches 2.35x slower, star misses 1.63x, guards 1.61x, cache hits 1.41x, and nested matches 1.29x over 21 paired processes. `_cache_keyable` preserves correctness, but the memos earn their small complexity by avoiding a recursive lifetime walk on the hot path. Artifacts: `/tmp/x2c-match-memo-ab.8di4Ks/`. |

## Ledger rules

- The live table contains only `open` or `confirmed` purposeless abstractions.
- Rejected searches remain in external run evidence; durable negative controls
  belong in calibration, not the live candidate table.
- Record current lines and a region source digest when reviewing a live row.
- Reinspect a row when its digest changes; do not carry its verdict forward.
- Keep mechanical hits and empty searches in the external run, not this table.
- Treat a forwarding chain as one candidate. Delegation without unique policy,
  transformation, lifetime, failure, or representation ownership is a primary
  search target.
- A confirmed row still requires separate authorization before deletion.
