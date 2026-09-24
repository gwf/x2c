# Standalone consolidation worklist

> Status: reference
> Source audit of `f28fc36`, recorded 2026-09-22. These are independent cleanup
> candidates, not approved implementation plans. Later `dev` changes have not
> been reassessed here; confirm each candidate against current source before
> implementation.

Baseline: `f28fc36fd11116666cf21962c66c5b27dda66d0b`, 2026-09-22.
All source ranges below are inclusive and were checked against this commit.
Links pin the audited commit and open the first line; the separate Lines
column identifies the full slice.

This report is about removing duplicated ownership, implementation, and work.
It stands independently of the [bug queue](bug-findings-f28fc36.md).
**Fixing a bug does not close a consolidation item if the duplicate owner or
computation remains.** Conversely, identical current output is not a reason
to keep two independently maintained implementations of the same fact.

No implementation is included or authorized by this report. Source counts
identify code under discussion, not promised net savings. Existing behavior
and ordinary verification still bound any later implementation.

## Worklist, ordered for consolidation rather than bug severity

"Bounded" means a concrete reuse/deletion boundary is identified, not that a
patch has been implemented. "Decision" means a stated contract or cost choice
remains. "Design" means a missing representation prevents immediate deletion.

| ID | Independent cleanup objective | Status | Definition of done |
| --- | --- | --- | --- |
| C01 | One builtin type/tag inventory | Done (02fa85d6) | 56 handwritten entries replaced by a projection of the existing ledger |
| C02 | One static signature-graph serializer | Bounded | Two Lisp serializer functions removed; all three consumer families use compiler literal caching |
| C03 | One native function-signature projection | Decision | Independent alias traversal/spelling/projection removed after compatibility policy is explicit |
| C04 | One runtime allocation/wrapper fact owner | Bounded design | Both graph classifiers and wrapper predicate consume existing compiler-owned facts |
| C05 | One graph direct/computed call recognizer | Done (70b23d6d) | Lifetime recognizer and flow forwarding wrapper removed |
| C06 | One graph source-location formatter | Done (c6ac7841), except flows | Five implementations reduced to one owner and calls |
| C07 | One static-storage acquisition template | Done (14843fc5) | Inferred and known-size branches emit the common protocol only once |
| C08 | One initializer evaluation policy, without recomputation | Shared policy bounded; metadata follow-up | File/local callers share expression classification; separately assess carrying per-binding decisions to emission |
| C09 | Docs consume compiler-selected definitions | Design | Docs no longer re-expand source macros or independently recognize declaration families |
| C10 | One primitive display-format policy | Cost/contract decision | One of the two tag-to-format switches removed without an unaccepted cost/behavior change |
| C11 | Recover each Match arm's pattern value once | Done (8fd9c740) | The arm pipeline stops recovering the same graph up to four times |
| C12 | One owner for typed Match guard interpretation | Design | Compiler consumes normalized predicate facts instead of decoding guard sugar independently |
| C13 | Shared lifetime summary/flow production | Design/measurement | Any larger rewrite demonstrably removes duplicate analysis or discarded production while retaining distinct outputs |

Suggested independent first slices: **C01, C02, C05, C06, C07, C11**.
They do not wait for bug triage, Context support, API metadata, or a Match
backend redesign. C04 and C08 have concrete shared-fact boundaries but need
careful preservation of the policies around those facts.

## C01. Derive builtin type/tag mappings from the existing ledger

| Implementation | File | Lines | Nominally shared work |
| --- | --- | --- | --- |
| Handwritten value rows in `typetags` | [src/type.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/type.x#L528) | 528-542 | Name each of 28 builtin value types and its Var tag |
| Handwritten pointer rows | [src/type.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/type.x#L543) | 543-557 | Repeat those 28 members for pointer tags |
| Authoritative object/symbol rows | [lib/var-tags.xmacro](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/var-tags.xmacro#L70) | 70-99 | Define the same builtin tag membership |
| Authoritative reference rows | [lib/var-tags.xmacro](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/var-tags.xmacro#L102) | 102-131 | Define their reference tags |

**Shared owner:** the existing Var ledger. `var.tag.filter` (168-170) and
`var.tag.descriptor?` (198-199) already select rows. The nearby `varrows`
projection at src/type.x:564 demonstrates the existing mechanism; its producer
is lib/var-tags.xmacro:366-375. The ledger is already imported at type.x:21.

**Connected edit:** replace the 56 manual entries with a compiler-facing Entry
projection. Make source-type spelling explicit: all 28 current names use the
initial-capital spelling of the tag, with corresponding reference tags.

**Delete:** the second builtin membership inventory at type.x:528-557.
**Retain:** native pointer C spellings at 514-527; scalar policy at 340-357;
unit-local custom tag registration at 584-621. Those encode different facts.

**Completion:** compare every old/new key and value, including pointer forms
and custom overrides. Adding a builtin should no longer require a second
membership edit in type.x. No runtime framework or runtime traversal is needed.

## C02. Delete the private Lisp signature serializer

| Duplicate implementation | File | Lines | Existing owner doing the same work |
| --- | --- | --- | --- |
| `lisp.native.list-item` | [etc/lisp-bindings.xlisp](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/etc/lisp-bindings.xlisp#L6) | 6-12 | `_cache_literal_var`, src/compiler.x:1905-1920 |
| `lisp.native.signature` | [etc/lisp-bindings.xlisp](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/etc/lisp-bindings.xlisp#L14) | 14-21 | `_cache_literal_list`, src/compiler.x:1922-1932 |
| Reusable public compiler entry | [src/compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L1938) | 1938-1941 | `Compiler.cache_literal_list` |

Both families recursively turn nested List/String/Symbol data into runtime
List expressions. Lisp explicitly emits boxing and cons calls; the compiler
already owns the literal graph and its cached materialization.

**Connected edit:** add only a narrow private macro callback into the existing
compiler entry, passing the **current signature data unchanged**. Redirect:

| Consumer | File | Lines |
| --- | --- | --- |
| Direct `$lisp.bind` | [etc/lisp-bindings.xmacro](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/etc/lisp-bindings.xmacro#L4) | 4-9 |
| Grouped `lisp.binding.call` | [etc/lisp-bindings.xlisp](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/etc/lisp-bindings.xlisp#L81) | 81-88 |
| Builtin `lisp.native._target` | [etc/lisp-bindings.xlisp](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/etc/lisp-bindings.xlisp#L104) | 104-108 |

**Delete:** the two serializer functions, 15 implementation lines across the
two ranges, before replacement glue. **Retain:** existing normalization and
signature spelling initially; fresh Func.new/Func.new_rest and group behavior.
This slice does not depend on resolving C03's spelling decision.

**Lifetime boundary:** store plain signature values in retained decorator
records; materialize cache expressions in the current consuming Compiler.
Never persist compiler-local cache IDs in declaration recipes or interfaces.
Keep fresh handles because Lisp.bind transfers ownership, whereas implicit
function-to-Func conversion uses a shared cached handle.

**Completion:** no private recursive serializer remains, and direct, grouped,
builtin/rest, startup and replay paths use the literal owner. Verify signature
data, initialization order, and signature/session storage lifetime. This is
removal of an entire duplicate operation even if no bug is found.

## C03. Consolidate signature policy separately from serialization

| Implementation | File | Lines | Repeated responsibility |
| --- | --- | --- | --- |
| `_func_signature_literal` | [src/lambda.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/lambda.x#L313) | 313-329 | Project typed function parameters/result into a Func signature |
| `_sdk_native_function_type` | [src/macros.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/macros.x#L473) | 473-486 | Project the same native declaration for Lisp |
| `_lisp_value_type`, `_lisp_resolve_type` | [src/macros.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/macros.x#L453) | 453-471 | Independently select semantic typedef names and walk aliases |
| `lisp.native.normalize-type`, `.function-signature`, `.name-signature` | [etc/lisp-bindings.xlisp](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/etc/lisp-bindings.xlisp#L23) | 23-43 | Scalar spelling, second parameter/result assembly, name-based reflection |
| Existing declared-type normalization | [src/compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L3241) | 3241-3258 | Canonical alias operation used for ordinary reference parameters |

Callers: ordinary handles at lambda.x:610 and 701; private callback registration
at macros.x:931-933; direct macro at lisp-bindings.xmacro:6-8; grouped reflection
at lisp-bindings.xlisp:59-79; builtin reflection at 41-43.

**Decision:** ordinary signatures retain non-reference aliases; Lisp resolves
most aliases and abbreviates scalars. Choose the shared owner's observable
signature-spelling policy. The nine-name whitelist preserves boxed names; it
is not a meaningless check to delete without preserving that role.

**Connected edit after that decision:** extract a pure typed-function-to-signature
operation from the ordinary path. Both callers use it; remove the private alias
walker, whitelist, abbreviation table, and second assembly as independent
policies. Keep a small syntax-to-type adapter where genuinely required.

**Retain:** actual native adapters, fresh session-owned Func allocation, fixed
versus rest constructors, and grouped registration checks. Do not replace the
macro by Lisp.bind(..., function): lambda.x:600-633 caches a handle, while
lib/lisp.x:2016-2021 transfers its storage to the session.

**Completion:** one signature policy and traversal-limit owner, verified with
the SAME aliased declarations on both paths and with observable error data.
C02 can land independently; an unresolved C03 must not hold it hostage.

## C04. Share runtime allocation and identity-wrapper facts

| Implementation | File | Lines | Repeated responsibility |
| --- | --- | --- | --- |
| Allocation rows in `runtime` | [src/regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L83) | 83-93 | Runtime name to result-storage owner |
| `_lifetime_named_allocation_kind` | [tools/x2c-graph/lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L169) | 169-182 | Independently name scoped/pooled operations |
| Named-call branch of `Lifetime.loop_allocation_kind` | [tools/x2c-graph/lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L149) | 149-164 | Independently name a narrower allocator set |
| Identity wrapper rows | [src/regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L98) | 98-103 | Twelve operations preserving argument identity |
| `_lifetime_transparent` | [tools/x2c-graph/lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L268) | 268-273 | Repeat eight of those wrapper identities |

Consumers: compiler `_summary` at regions.x:237-246, `_fact_of` at 250-267,
`_birth` at 301-328; graph birth classifier at lifetime.x:184-210, known-call
classification at 371-381, and direct loop collection at
loop-allocations.x:43-57. These are live paths, not obsolete tables.

**Shared owner:** expose small pure queries at the existing compiler region
owner, which the graph tool already imports. Keep result ownership separate
from argument retention/consumption/control effects at regions.x:94-97 and
104-116. Active Scope, explicit Scope argument, pooled result and unknown are
different answers; do not collapse them into one Boolean.

**Delete:** the 14-line graph name classifier, repeated name/kind decisions
at lifetime.x:154-163, and six-line wrapper predicate. **Retain:** graph AST
literal recognition at 132-148, source labels, type-conversion preservation
rules at 99-110, and each analysis's precision policy.

**Compatibility boundary:** first remove independent fact ownership without
silently broadening any public query's coverage. Where a consumer intentionally
supports a subset, make that a consumer capability distinction, not another
handwritten allocator vocabulary. Result facts must not imply that a copying
constructor retains its input or that an interned result always allocates.

**Completion:** adding/changing a runtime ownership or wrapper fact requires
one definition. Both graph consumers derive their answers from it. This does
not require Context support or replacement of either full flow engine.

## C05. Remove duplicate graph call-target recognition

| Implementation | File | Lines | Same decisions |
| --- | --- | --- | --- |
| `_lifetime_callee` | [tools/x2c-graph/lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L34) | 34-66 | Unwrap call, recognize automatic/computed target, recover emitted name |
| `project_call_target` | [tools/x2c-graph/targets.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/targets.x#L29) | 29-63 | Same decisions, plus stable local/public target identity |
| `_flow_target` | [tools/x2c-graph/flows.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/flows.x#L37) | 37-40 | Pure forwarding call to project_call_target |

Double interpretation occurs at lifetime.x:296-305 and 484-502. The defer
consumer is at 720-737; other shared-owner consumers are flows.x:60-63,
133-153 and loop-allocations.x:156-170.

**Connected edit:** extend the existing target operation to optionally return
captured arguments and unwrap `stmnt`; migrate lifetime callers as one family.
Keep its current full `(args ...)` shape or adjust all consumers together.

**Delete:** the 33-line lifetime recognizer and four-line forwarding wrapper.
**Retain:** computed/automatic classification, emitted-name fallback, stable
local target identity and ambiguous-public resolution. This does not change
which calls the graph can resolve.

**Completion:** one operation decides direct/computed targets; callers obtain
name, target and arguments from that decision rather than parsing twice.

**Status:** done in 70b23d6d. `project_call_target` now unwraps `stmnt` and
optionally returns the call's `(args ...)`; graph outputs are unchanged.

## C06. Collapse five graph source-location formatters

| Function | File | Lines | Representative callers |
| --- | --- | --- | --- |
| `_source_location` | [tools/x2c-graph/x2c-graph.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/x2c-graph.x#L190) | 190-199 | 255-259, 348-362, 1062-1065 |
| `_lifetime_location` | [tools/x2c-graph/lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L118) | 118-128 | 250-260, 475-480, 580-587, 603-610 |
| `_loop_location` | [tools/x2c-graph/loop-allocations.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/loop-allocations.x#L28) | 28-37 | 51-56, 161-169 |
| `_flow_location` | [tools/x2c-graph/flows.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/flows.x#L25) | 25-35 | 133-168 |
| `_clone_location` | [tools/x2c-graph/clones.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/clones.x#L142) | 142-151 | 201-204 |

All obtain the Compiler origin, choose its display path or the caller's
fallback, and form `(location PATH LINE COLUMN)`; absent origins use zeroes.
Different holder structs merely supply the same three inputs.

**Connected edit:** make one existing graph location operation shared,
accepting Compiler, fallback path and origin. Pass those inputs directly.
**Delete:** four repeated implementations. Bodies total 52 lines; retain one
roughly ten-line body plus caller adjustments, not five compatibility wrappers.

**Completion:** a formatting/fallback rule has one implementation. Preserve
exact report rows for real and absent origins across all five consumer families.
No compiler analysis changes or runtime framework are required.

**Status:** done in c6ac7841 for four of the five. `project_location` in
targets.x replaces the x2c-graph, lifetime, loop-allocation and clone
formatters. `_flow_location` remains: it prints line and column as long
integers (`22l 3l`), so replacing it would change `flows` output.

## C07. Emit the static acquisition/cleanup protocol once

| Branch in `Emitter._local_static` | File | Lines | Duplicated protocol slice |
| --- | --- | --- | --- |
| Inferred-size array | [src/emit.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/emit.x#L368) | 368-395 | 377-390 |
| Known-size object | [src/emit.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/emit.x#L396) | 396-418 | 403-417 |

Both produce guard/pointer storage, acquire, cleanup registration, payload
copy, commit, cleanup leave and final payload-pointer assignment. `_static_copy`
at emit.x:301-316 is already shared; the surrounding protocol is not.

**Connected edit:** prepare branch-specific type, source-operand, mapping and
declaration fragments, then emit one common protocol template. Apply
`_initializer_macro` only around the inferred case.

**Delete:** the second protocol template, approximately 15-20 repeated lines
before replacement glue. **Retain:** inferred `__typeof__(formal)` and probe
mapping; known-size assertion and typed temporary; exact operand evaluation,
cleanup registration, copy/commit and publication order.

**Completion:** the acquire/commit/abort ordering can be changed in one source
template, with inferred/known-size behavior and existing once/retry/threaded
fixtures preserved. This does not require a full cleanup-AST redesign.

## C08. One initializer-expression classifier; preserve its decisions

| Similar implementation | File | Lines | Consumers |
| --- | --- | --- | --- |
| `_needs_runtime_initializer` | [src/cache.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/cache.x#L546) | 546-554 | cache.x:292, 298, 339 |
| `Compiler.static_value_is_runtime` | [src/cleanup.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/cleanup.x#L269) | 269-340 | cleanup.x:352; emit.x:355 |

Both traverse initializer expressions and decide which operations require
execution. They independently encode the normalized expression vocabulary
and operand-evaluation rules. Those are shared language facts, regardless of
whether a regression happens to expose a disagreement.

**Connected edit:** evolve the existing Compiler query into the common typed,
normalized-expression owner. File callers query initializer values through it.
**Delete:** cache.x:546-554, not the surrounding file placement policy.
**Retain:** local binding/address rules, file dependency ordering and deliberate
nonconst-static deferral; placement and storage construction remain separate.
The relevant policy wrappers are cache.x:284-319, 333-349 and
cleanup.x:342-358, 364-384. No generic AST visitor is called for.

**Completion of the first slice:** one expression grammar/evaluation policy
is maintained. Nine existing lines are a precise deletion target, not a net
size estimate; adding extra special cases to both predicates does not finish it.

There is a second, distinct repeated-work opportunity:

| First decision and information loss | Repeated decision |
| --- | --- |
| cleanup.x:342-358 classifies each binding and records names in a pass-local map, but does not carry per-binding decisions to emission | emit.x:339-359 iterates the same bindings and classifies them again |
| cleanup.x:364-384 emits `(localinit declaration body)` without per-binding status | emit.x:318-422 must recover which bindings need runtime storage |

Assess carrying per-binding decisions in the existing lowered localinit node,
not a global cache. Keep the emitter's necessary binding/storage walk. Mixed
declarations, nested runtime dependencies and post-cleanup qualifier changes
must be accounted for before declaring those decisions reusable unchanged.
This follow-up is a bounded design question, not an established net deletion.

## C09. Remove docs' independent declaration/macro interpretation

| Nominally shared task | Documentation implementation and lines | Compiler owner and lines |
| --- | --- | --- |
| Identify function definitions and bodies | [x2c_source.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c_source.py#L739): function_spans 739-790; definitions 793-830 | [parse.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/parse.x#L1429): _finish_function_parts 1429-1482; _finish_function 1485-1495; parse_function_definition 1527-1534 |
| Determine functions produced by a Unit macro | [x2c_source.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c_source.py#L656): _unit_macro_definitions 656-736; import/concatenation path 833-873 | [macros.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/macros.x#L2536): expand_macro_invocation_node 2536-2636, especially substitution/binding 2608-2630 |
| Recognize foreign-alias definitions | [x2c_source.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c_source.py#L509): _foreign_alias_definitions 509-559 | [parse.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/parse.x#L1966): finish_foreign_alias 1966-2014 |

These are similar responsibilities, not equivalent parsers: the Python side
approximates selected source forms while the compiler actually selects, binds
and types the resulting definitions. That is precisely why docs should consume
the selected result instead of maintaining a second expanding shape grammar.

Current joining/enumeration consumers:

| Consumer | File | Lines |
| --- | --- | --- |
| Authored-definition/class-default join | [tools/x2c_symbols.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c_symbols.py#L356) | 356-395 |
| API callable/type collection | [tools/gen-api-reference.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/gen-api-reference.py#L604) | 604-650 |
| Module catalog | [tools/gen-module-catalog.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/gen-module-catalog.py#L30) | 30-44 |
| Special C API scanner route | [tools/gen-api-reference.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/gen-api-reference.py#L1016) | 1016-1027 |

**Required design:** a compiler projection of selected definitions with origin
and doc attachment, distinct from imported prototypes. Current interface
function rows and selected declaration recipes (x2c_symbols.py:295-353) are
not yet a demonstrated complete emitted-definition inventory.

**Delete after that representation exists:** documentation-facing macro text
substitution and special function/foreign/decorator discovery; migrate all four
consumers. The source scanner still serves metrics and other span analyses,
so retiring a docs dependency is not permission to delete every shared scanner
function. Keep prose extraction, ordering, public exclusions and source links.

**Completion:** one new legal definition form needs compiler support only,
not another documentation grammar patch. A new reverse validator without
removing the private interpretation path is an interim check, not completion.

## C10. Consolidate primitive display formatting if the cost is acceptable

| Implementation | File | Lines | Shared policy |
| --- | --- | --- | --- |
| `_primitive_str` | [lib/dispatch.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/dispatch.x#L506) | 506-522 | Primitive tag to display format |
| `_write_primitive_str` | [lib/dispatch.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/dispatch.x#L542) | 542-556 | The same mapping, writing a Buffer |
| Existing one-owner precedent | [lib/dispatch.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/dispatch.x#L503) | 503-504, 657-681 | _primitive_repr delegates to streaming representation |

**Concrete alternative:** make primitive String rendering use the streaming
owner just as repr does; delete its second format switch. Retain descriptor
dispatch and both public APIs. This is a small real duplicate, not refuted
merely because its outputs currently agree.

**Decision:** String.printf (string.x:1108-1134) uses short-value stack staging;
Buffer.printf (buffer.x:182-198) plus str_free (336-339) adds allocation/copy/free.
Their formatting-failure behavior also differs: NULL versus a format raise.
Measure the relevant path and decide that contract before choosing delegation.
A runtime format selector is not an equivalent cheap substitute because Var
variadic arguments require a static format (transform.x:164-181).

**Completion:** one tag-to-format policy remains, with accepted allocation and
failure behavior and byte parity. No generic formatting framework is proposed.

## C11. Stop recovering the same Match pattern graph repeatedly

| Recovery consumer | File | Lines | Repetition |
| --- | --- | --- | --- |
| `match_pattern_value` implementation | [src/compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L1956) | 1956-1979 | Recursively recovers values through caches/typed wrappers/cons |
| `match_pattern_head_symbol` | [src/compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L1999) | 1999-2007 | Recovers before inspecting the head |
| `match_pattern_flat_head` | [src/compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L2030) | 2030-2049 | Calls head query at 2032, then recovers again at 2034 |
| `match_pattern_is_static` | [src/compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L1990) | 1990-1991 | Recovers again |
| `_match_arm_label` | [src/emit.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/emit.x#L717) | 717-729 | Calls head query again at 720 |
| Per-arm calling sequence | [src/emit.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/emit.x#L777) | 777-783 | Invokes flat, static and label queries for the same arm |

A literal-headed arm while labeling is active causes four top-level recovery
traversals. Static-ness is also computed for successful flat arms, though its
answer is only used by the fallback branch.

**Connected edit:** recover once in `_match_if`; derive head once; pass the
value/head to narrower classifiers and the label builder; evaluate static-ness
only for fallback selection. Keep source-order emission effects unchanged.

**Delete:** redundant recoveries/head analysis along this arm path, not the
shared recovery implementation. **Retain:** AST-taking wrappers needed by other
consumers, including emit.x:462 and 607. No persistent cache, new pattern IR,
or change to native/runtime matching is necessary.

**Completion:** one recovered graph per arm feeds all these consumers, with
identical generated behavior. This is source-proven repeated work; no timing
gain or net line reduction has been measured. It is independent of C12.

## C12. Share typed Match guard interpretation, not execution machinery

| Independently interpreted fact | Compiler location | Runtime owner |
| --- | --- | --- |
| Leading binder in `(!is binder type tag)` | [compiler.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/compiler.x#L2012), _flat_capture_tag 2012-2022 | [match.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/match.x#L332), normalization 332-344 |
| Type-tag alias treatment | compiler.x:2018-2020 excludes aliases | match.x:686-690 canonicalizes them |
| Normalized type predicate | compiler's tag extraction above | [match.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/match.x#L1342), lowering 1342-1351 |

MatchCaptureLayout already constructs normalized pattern data at match.x:556-596
and stores it at 588. Compiler binder analysis at compiler.x:2055-2062 consumes
binder lists and frees that layout; emission does not receive the normalized
value.

**Possible shared owner:** a Match-owned normalized type-predicate operation,
used by runtime lowering and compiler eligibility. Delete independent guard
sugar/alias interpretation only when both truly consume that operation.

**Unresolved design:** how to carry or obtain normalized facts without costing
more than the removed work. Moving _flat_capture_tag into another file alone
does not consolidate anything. Preserve specialization eligibility unless
expansion is deliberately approved.

**Retain:** direct C condition emission at emit.x:735-754, runtime matching,
canonical binder layout and distinct capture-publication contracts. Decoding
MatchPlan wordcode into C is not a demonstrated small deletion. C11 should
not wait for this design or for a new performance experiment.

## C13. Larger lifetime sharing: locate overlap without pretending equivalence

| Nominal work | Compiler implementation | Graph implementation |
| --- | --- | --- |
| Return/allocation summaries | [regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L237): _summary 237-246; _flow 339-392; _analyze 774-794; _fixpoint 799-814 | [lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L275): _lifetime_summary_fact 275-306; _lifetime_typed_summary_fact 308-318; _lifetime_resolve_summary 867-898; _lifetime_summaries 900-928 |
| Bindings, blocks, returns, control flow | [regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L534): _assign 534-563; _walk_block 692-701; _walk 703-750 | [lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L523): _lifetime_bind 523-554; _lifetime_return 575-640; _lifetime_block 662-681; _lifetime_isolated_walk 683-699; _lifetime_statement 701-795 |

These are explicit comparable slices, not a claim that their bodies are
interchangeable. Compiler MAY-fresh plus sinks differs from graph MUST-return-
one-kind. Graph also keeps Context association, branch snapshots, uncertainty,
birth/end locations and stable query schemas. Context alone is neither a
reason to preserve everything nor a sufficient prerequisite for deleting it.

There is a separately identifiable wasteful production path:

| Producer/consumer | File | Lines | Actual work |
| --- | --- | --- | --- |
| Loop analysis invokes full lifetime analysis | [loop-allocations.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/loop-allocations.x#L190) | 190-216; call 208-215 | Additional whole-function analysis after collecting loop sites |
| Lifetime producer | [lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L797) | 797-859; state 810-827; output 848-858 | Produces escape state/findings/locations/unresolved records as well as return facts |
| Loop finish and resolver | [loop-allocations.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/loop-allocations.x#L339), [lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L969) | 339-353; 969-986 | Uses return summaries through _lifetime_functions at lifetime.x:937-947 |

**Design objective:** derive both analyses' required facts from shared owners
and stop producing discarded escape-report data for the loop query. Preserve
reassignment and unknown-call effects needed for return facts. Do not create
a second summary walker or many flags just to skip a few allocations.

**Completion boundary:** either demonstrate a smaller shared implementation
retaining both precision contracts and schemas, or retain the separation with
measured justification. No entire walker/file deletion or speedup is claimed
now. C04-C06 are available independently and must not be deferred behind this.

## Implementation packets and acceptance

| Packet | Scope | Must disappear | Independent of |
| --- | --- | --- | --- |
| Ledger projection | C01 | Second builtin inventory | All bug fixes and other consolidation |
| Literal materialization | C02 | Lisp recursive serializer | C03 alias policy |
| Graph shared helpers | C05-C06 | Duplicate call recognizer, forwarding wrapper, four location bodies | Context/flow redesign |
| Emitter template | C07 | Second acquire/cleanup protocol template | Full cleanup AST lowering |
| Match arm data flow | C11 | Repeated value/head recovery | Match backend/guard redesign |
| Ownership facts | C04 | Independent named allocator and wrapper classifiers | Whole lifetime engine retirement |
| Initializer semantics | C08 first slice | Second expression-evaluation classifier | Localinit metadata optimization |

For every implemented packet, review the authored diff for actual removal of
the identified second owner or computation. Replacing a duplicate with another
registry, a forwarding-only abstraction, an extra validator, or an unchanged
copy in a new file is not completion. Use existing relevant fixtures and the
repository's normal final gate; this catalog adds no recurring test/process.

C03, C09, C10, C12 and the larger C13 work need their named decisions or design
evidence. They are not reasons to postpone the bounded packets above.

## Scope and evidence

This is a report revision and source-range verification of the prior review,
with independent compiler, native-binding, and lifetime reviewers. It adds
the precise repeated Match recovery and localinit recomputation slices; it
does not claim a fresh exhaustive audit of every repository file. The audit
used the stated clean HEAD. Splitting the reports did not change production
code or add behavioral probes. Checking these reports into later `dev` records
that historical evidence; it does not revalidate the findings on that branch.

The earlier mixed report and individual reviews were workspace investigation
notes. The source evidence and actionable boundaries needed for consolidation
are retained here; defect evidence and reproductions are in the separate bug
report. Neither report requires access to those temporary notes or reading the
other report.
