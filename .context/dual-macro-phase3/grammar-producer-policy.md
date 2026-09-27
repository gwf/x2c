# Revised compiler-template policy: lowered producers and compiler facts

Read the revised pasted request at
`/Users/gary/.codex/attachments/645ec637-6471-4b94-a632-4914d2cbe2f4/Pasted text.txt`.
This supplements and **supersedes** grammar.md's recommendation that compiler
clients permanently retain raw `%()` exceptions. No production source changed.

Compiler lowering clients use the frozen four forms plus ordinary meta calls
in template slots. They do not inspect macro descriptors, capture rows or stage
markers, and do not construct lowered canonical heads with `%()`. Named meta
producer functions own those structures. Producers remain ordinary x2c meta
functions, not new syntax forms; their implementation can use canonical List
construction. Ordinary compiler binding/typing/lowering owners retain semantic
authority. Private names below are proposed names grounded in current owners,
not already implemented APIs. One producer can cover related shapes, but each
shape has exactly one authoritative producer owner.

## Lowered/non-source production -> proposed meta producer

Each function receives ordinary supplied syntax/data arguments. Stage marks and
effects are conveyed by the common private result adapter; client source never
opens that envelope. `%()` appears only inside the named producer (or its
private structural helper), not at lowering call sites.

| Canonical production | Proposed producer and argument facts | Current authoritative owner / client use |
| --- | --- | --- |
| cache constant graph reference | `_constant_syntax(value)`; receives immutable value, returns code plus intern-constant effect instead of inventing process-local ID | compiler.x:2248-2326; stage.x:119-136. Template slot calls it for constant data. Compiler applies interning and supplies the cache reference. |
| localinit declaration/body | `_local_static_region(declaration, body)`; already bound declaration and remainder body, lower-stage result | transform.x:2037-2057,1836; emitter local-static. Static planner passes both; template contains only slot call. |
| sourceinit helper function | `_source_initializer(function, order)`; function syntax plus caller-supplied initializer order/dependency facts | cache.x:451-468; emit.x:1060. File-initializer producer owns wrapper and effect scheduling. |
| guarded Match case body | `_guarded_match_arm(condition, body, capture_plan)`; returns arm control shape with guard retry/fallthrough intent | statements.x:368-373; parse.x:2877; emit.x:586. Existing `case ... if (...)` source template can generate it directly; compiler migration never spells guarded. |
| resolved tadapt origin/source | `_typed_callback_adapter(target_type, source, adapter_facts, site)`; compiler supplies resolved target/source facts and memo lookup/allocation plan | expressions.x:2420-2437, transform.x:165-264. Existing `$adapt` can remain source route; producer owns resolved marker/helper effects, not a second adaptation validator. |
| matchcases subject/derived binder rows | `_lower_match_cases(subject, arms, capture_layouts)`; compiler passes existing MatchCaptureLayout-derived facts | transform.x:3076-3088. Client uses ordinary match template or slot producer; producer owns derived rows. |
| varray converted elements | `_var_array_literal(elements)`; receives already converted Var expressions | transform.x:3528-3535. Conversion facts supplied by ordinary owner before meta; producer emits lowered literal node. |
| vmap/vpair converted pairs | `_var_map_literal(pairs)`; ordered already converted key/value expressions | transform.x:3538-3551. Same, single producer owns vpair child rows too. |
| initval input/alternatives tables | `_initializer_alternatives(inputs, alternatives)`; compiler supplies destination types, selector paths, native condition facts and converted values | expressions.x:3922-4003, ast.x:241-249. Meta producer builds exact alternative table without repeating conversion/type rules. |
| initcode input/body | `_initializer_code(inputs, body)`; previously computed input placeholders and initialization statements | cache.x:265, emit.x:1057. Producer owns emission-macro representation. |
| managed-init value marker | `_managed_initializer(value, ownership_facts)`; caller supplies current ownership/placement decision | expressions.x:2059-2062, parse.x:2593, transform.x:4125. Existing source ownership macros remain source surface. |
| lowered callable defer with env/callback/capture records | `_callable_cleanup_region(body, capture_plan, cleanup)`; compiler passes written/reference mode/type facts; result effects allocate/register environment and helper in stable order | transform.x:3755-3818. Client unary defer template plus slot call; producer owns capture record layout. |
| var boxing / cons / append / string / nil cache graph internals | `_literal_value(value, conversion_facts)` shared with `_constant_syntax`; no new producer per cons cell unless ordinary owner requires it | compiler.x:2275-2326, transform.x:4250-4253. Ordinary source literals/List operations are preferred client spelling. Raw graph construction stays inside literal producer. |
| at/src/api-source wrapping | `_located_code(code, site)` and `_captured_source(code, capture_facts)`; precise complete-source facts only when supplied by compiler | parse.x:2477-2489,2738, macros.x:3778-3820. Common producer/result adapter attaches ancestry; templates never author origin IDs. |
| pending template invocation / macro-slot / meta-call captures | `_template_slot_result(value, stage)` common internal adapter; generated by four forms and meta slot calls, not an explicit client operation | macros.x:2490-2510,2965-3029,3971-3985,4160-4269. Compiler source never opens records; source syntax selects operations. |
| declaration bundle/recipe/pending/forward/default/function | `_declaration_result(code, production_facts)` common declaration producer; separate private `_default_forwarder(child,parent,member,fallback)` when semantic owner needs it | parse.x:2505-2557,2675-2716. Compiler client uses ordinary Declaration/NamedType source templates or meta producer calls; once-only production facts remain ordinary owner data. |
| comment/space/src-at emission decorations | `_emission_origin(site)` and existing formatter/emission operations; not syntax-template transforms | emit.x:1024-1030, generate.x:1150. If refactored, producers alone build token decorations; no invented source keyword. |
| generated C helper function, static record, guard, forward tag | named source templates `_callback_function`, `_func_adapter_function`, `_protocol_guard`, `_file_initializer`; producer fills type/name/value slots and returns registration effects | transform.x:139-162,434-505; generate.x:124,254; protocol.x helper synthesis. These **do** have source grammar and need no lowered AST producer head. Source templates replace their raw function/declaration skeletons. |

This includes administrative shapes for completeness, while distinguishing them
from strictly lowered-only nodes. `tadapt` and `guarded` are not entirely
lowered-only: existing source operations already produce their resolved forms.
The corrected field grammar documents both stages. Metadata such as adapter
memo keys, semantic binding facts and protocol conformance maps is not program
AST and need not receive public syntax-template forms. Meta producers can
construct their effect/argument data privately.

## Mid-template facts: helper functions cannot query the compiler

Current `_try_block` and `_defer_block` arguments already carry body, frame,
handler, cleanup bodies, environment/callback and captured record facts, but
also carry Walk/Compiler handles. A helper-process meta function must not retain
or dereference those handles. Split compiler decision/planning from source shape:
the ordinary compiler planner computes the following facts before executing the
meta function. The meta function returns code plus effects; the compiler applies
effects at its insertion transaction. Do not turn a needed query result into
an effect whose result the helper somehow reads synchronously.

| Current query/result needed by construction | Already supplied? | Contract-preserving input to producer |
| --- | --- | --- |
| frame/handler/callback/record binding identities and captured field types | Mostly yes: _try_block/_defer_block parameters and records | Pass the existing issued Name values and Type values. `_region_binding` IDs must not be freshened again. Additional allocation is an ordered request resolved by caller plan before dependent meta slots, or one planned symbolic effect set, not native helper-issued program IDs. |
| whether each catch pattern is static, selecting ERROR_CATCH_PENDING/TRANSIENT | No: _try_block calls `c.match_pattern_is_static(pattern)` mid-loop (transform.x:2376) | Pass per-arm static facts or already selected catch-state value from ordinary Match owner; meta code only lays out arm preparation. |
| target-unit runtime helper bindings and full signatures | No to meta-only template: `_adapter_helper` calls sym.resolve_global (transform.x:318-319); current try calls use known raw runtime names | Caller supplies resolved Name/Expr+signature facts, or the approved open free-name mode lets ordinary skeleton binding resolve them in target unit. A resolve-global effect alone cannot let helper code branch on the returned Type before compiler application. |
| source/target semantic type resolution, pointer/function/aggregate/numeric classification | Not always: typed adapters and _checked_func_argument query `sym.resolve_key` (transform.x:127-135,184-195,295-308,363,450-483) | Ordinary Type/adapter planner passes normalized Types, approved conversions and representation classification. Do not copy sym resolution into a helper semantic validator. |
| per-argument conversion expression and result conversion | No: `_callback_function` calls convert_expression during skeleton construction (transform.x:151,157); _checked_func_argument:360-401 | Keep ordinary conversion owner outside helper query boundary; pass converted expressions, or bind an unbound source skeleton with ordinary conversion rules. Bound/lowered slots are trusted unchanged, so they must already carry the conversions required by their call/declaration boundary. |
| native helper memo hit, binding, signature and diagnostic type | No: $adapter.memo / normalize_declared_type / add_early surround current producers (transform.x:255-264,321-339,513,646,661,719) | Compiler supplies cache outcome and known function facts before helper execution. Helper returns a memo-insert/helper-registration effect only for a miss, with deterministic logical references. No helper-local cache decides compiler identity. |
| current diagnostic origin and location | No: implicit c.origin throughout lower_typed_adapter_expr and transfer walks (transform.x:183,194,1848) | Pass explicit caller-owned site/ancestry facts to producer. Helper may return diagnostic data; compiler reports it at supplied site. It cannot manufacture source span ownership from structural equality. |
| cleanup statements and placement order | Inputs supplied, placement decided in _try_block/_defer_block (transform.x:2288-2417) | Producer returns explicit cleanup-placement intent tied to passed region Name/site; existing region/transfer owner applies it. Generated code preserves statement order, including unhandled branch cleanup. Do not use a generic tree append effect. |
| target protocol/index/slice helper selection, representation field paths | Not always: transform.x:3158-3183,4172-4235 queries helper/type owners | Compiler passes selected callee/type/conversion facts or already bound expressions. Structural template chooses no protocol implementation itself. |
| literal cache IDs and initializer placement dependencies | No: cache.x:248-265,462-468 allocates generated helpers and graph slots | Meta functions return interning/initializer scheduling effects; compiler owns IDs, order and source/header placement. Any dependency needed to compute a later slot must be planned before that meta call. |

Pure operations on supplied canonical Type Lists are not compiler queries if
they require no Sym/ledger facts. Alias resolution, field layouts, protocols,
active scopes and binding registration do require compiler context. The field
grammar is documentation of those facts, not an authorization to rebuild their
semantic owners in the helper.

## Derived fields: ignore annotation, preserve relations

The revised instruction “recognition ignores derived fields” cannot mean erase
all derived content. `binding ID` is derived, but equality of references and
references-to-declarations is semantic syntax structure. CacheID is derived but
must be dereferenced using its owner before comparing cached constant meaning.
Generated region/callback identities likewise carry relations and lifetime.

Apply the existing normalization distinction:

* Ignore incidental diagnostic ancestry, outer inferred Expr type and return
  context when comparing the agreed syntax stage.
* Normalize owned lexical binding identities to local scope slots, preserving
  repeated/reference relationships, shadowing and injectivity. Compare external
  reference identity interfaces rigidly; do not wildcard every binding record.
* Preserve explicit Type syntax operands, source operator/member names, capture
  value relationships and lowered control/placement markers. These are not
  disposable annotations even if a compiler computed their representation.
* Return original syntax captures where available; comparison projection does
  not invent source text for rebuilt or interior syntax.

The S/D field annotation describes origin of a field, not whether semantic
recognition may discard it. The contract needs both origin and comparison policy
columns. Mixed Name prototype demonstrates the concrete distinction: Name's
compiler-issued binding is not compared by its numeric spelling, yet the same
reference must target it and the member projection must agree with Name spelling.

## Evidence and limits

Canonical producer table and query sites are source-backed proposals. No meta
producer effect ABI, staged insertion transaction rollback proof or byte-identical
try/defer rewrite has been implemented by this worker. Parent's integration and
effects worker own those proofs. The existing ordinary named Param-sequence
wrapper executes 6 and mixed Name private constraint probe executes 1/0/1/0.
The latter proves viable projection constraints, not complete automatic four-form
Name recognition. Field grammar/census cover described AST owner shapes but
explicitly retain dynamic-head/raw-C fallback and semantic Type subrecord proof
gaps. Helper transport and REPL interpreter isolation remain separate tracks.
