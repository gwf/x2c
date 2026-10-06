# Compiler and library review coverage

> Status: done, 2026-09-30; the coverage record for PR #72 (2685655f).
>
> Earlier status: reference. Independent review completed on 2026-09-30.
> Source: origin/dev cfd8324c2a1db623a738d409b18fe3a5f7e0cbea.
> Proposed next-pass changes remain unimplemented.

This record accompanies the [ranked plan](compiler-library-beautification-next.md).
It preserves file coverage and its limits without depending on ignored local
workspace notes. Independent first impressions preceded each partition's
relevant dev-plan/history reconciliation. No main-based campaign supplied
findings. All review workers verified the explicit dev SHA before source reads.

The direct source inventory is 40 compiler and 71 library .x/.xmacro files:
110 authored files plus generated src/linked-meta.x. Generated lib/x2c.x stays
under its Makefile owner. No files are missing or assigned twice. Compiler
inventory totals 47,780 lines and library 33,358; these are inventory counts,
not executed paths or a uniform every-line certification.

The 19driver/meta files have complete-operation review with explicit large-file
gaps. Seven semantic and 14 parser/backend bodies were fully read. The 43 library
values/Lisp/Match and 28 lifetime/IO/thread files have body/operation ledgers.
Tests/books listed by each packet were reviewed; only controls explicitly
identified as executed in the plan establish executable evidence. Clean
baseline probes and integrated mitigation validation are separate.

## Compiler driver and meta

19 files, 19,642 inventory lines.

| File | Lines | Operations reviewed | Gap or retained boundary |
| --- | ---: | --- | --- |
| [src/main.x](../../src/main.x) | 700 | Full command/translation/build/worker lifecycle, per-target Context, preload, stale unit registration, env/external command and script closure paths | No host-specific external command integration rerun |
| [src/cli.x](../../src/cli.x) | 1237 | Request/option ownership, parse/apply, response quoting/UTF-8, package-native admission, help metadata | Not every individual option/help string or invalid CLI permutation |
| [src/frontend.x](../../src/frontend.x) | 472 | Positioned unit start/close, library preload, package configuration, native preprocessing and shared session transfer | No overlay/recovery fuzzing |
| [src/compiler.x](../../src/compiler.x) | 4342 | Record and sharing/transfers, Sym binding facts, semantic transaction commit/rollback/transient, literal index/pattern value recovery, retained syntax, shared collection/full parse and script hoist operation | Declaration-default producers, all typedef/protocol combinations and diagnostic recovery not individually probed |
| [src/build.x](../../src/build.x) | 1270 | Request preparation/artifact placement, stale translation records, generated includes, compile pool, final publication, script helper/cache fingerprint, module entry and extension ownership | Native concurrency/TOCTOU and linker platforms not stress tested |
| [src/project.x](../../src/project.x) | 902 | Manifest sections/field/value parsers, target planning/lowering, dependency/native module/source selection, profile flag ordering, lock/starter paths | Every cyclic/invalid manifest, glob and package index path not executed |
| [src/toolchain.x](../../src/toolchain.x) | 464 | Full argv/tool layout, ToolRun start/wait/capture, preprocess outputs/dependencies, compiler search dirs, quoted display | Windows/Linux/native-tool variants not executed |
| [src/install.x](../../src/install.x) | 479 | Lock/staging/publish, bundle/source build, markers, installed versions, remove/list | No network/package install/remove performed |
| [src/script.x](../../src/script.x) | 148 | Complete script preparation, lock/cache/prune/run lifetime and Build consumers; baseline local/runtime include controls executed | No cache race stress |
| [src/editor.x](../../src/editor.x) | 256 | Complete finite-request setup, overlays, source facts, occurrence selection and response lifetime | No live editor/client integration |
| [src/report.x](../../src/report.x) | 281 | Complete progress/receipt formatting and terminal ownership/write lifecycle | No interactive-terminal/fork interleaving stress |
| [src/utils.x](../../src/utils.x) | 434 | Complete environment/source/package/hash/file-lock/atomic-publish/worker owners | Alternate OS environment and host failures not executed |
| [src/macros.x](../../src/macros.x) | 5550 | Definition/capture roles, invocation/Expansion binding/hygiene, rebuild and Macro value lifetime paths, meta installation/calls/subjects, shared library and native lifetime/registry/linked hashing, SDK/source cutpoints | Not every SDK query/diagnostic, import route or 5,550-line branch path executed; B1/B2 remain source-only designs |
| [src/stage.x](../../src/stage.x) | 440 | Complete argument/folded result/literal/data/compile-time-only operation, retained numeric/Var boundary distinctions | Broad constant-arithmetic policy deliberately excluded |
| [src/meta-group.x](../../src/meta-group.x) | 866 | Complete group membership/reachability/source order/lower/native entry/static reset/emission isolation/module staging lifecycle | In-process failure identity/cache invalidation controls remain B4 prerequisites |
| [src/meta-project.x](../../src/meta-project.x) | 607 | Owner discovery, include/import/package/source kind boundary, host flags, group/helper build/support/link/manifest/cache lifecycle | No cross-compilation or failure/concurrency campaign |
| [src/meta-helper-client.x](../../src/meta-helper-client.x) | 358 | Complete request/reset/send/frame/receive/deadline/process/reaping/lifecycle ownership | Earlier bounded send-deadline fix is already separate delivered work; no shutdown redesign |
| [src/linked-meta.x](../../src/linked-meta.x) | 817 | Generated inventory and representative emitted bodies, binding/hash consumers and authoritative generator wiring | Generated bodies are derived source, not independently maintained copies; no regeneration here |
| [src/ast-rewrite.x](../../src/ast-rewrite.x) | 19 | Complete conditional prefix copy/order/return macro and Macro walk caller eligibility | Candidate usage effect/allocation identity controls remain required |

## Compiler semantics

7 files, 11,285 inventory lines.

| File | Lines | Operations reviewed | Gap or retained boundary |
| --- | ---: | --- | --- |
| [src/type.x](../../src/type.x) | 986 | All source; declaration-to-Type conversion, prototype declarator qualifiers, canonical/declared forms, qualifier discard checks, scalar specifier grammar, promotions/usual arithmetic conversion, literal magnitude/suffix selection, designated object projections, fixed and unit-local Var tag registration/lifetime. | Keep canonical versus declared distinction. No new numeric grammar/radix/host-width matrix; no allocation-failure injection in local Arrays. |
| [src/type-ledger.x](../../src/type-ledger.x) | 42 | All source; native pointer and boxed tag rows, shared Var-ledger projections, process-lifetime accessors versus per-unit declared tags in type.x. | No new tag encoding or ABI proposal. Shared compiler/runtime ledger already exists. |
| [src/protocol.x](../../src/protocol.x) | 2860 | All source; canonical source paths, occurrence/adoption publication and conflicts, lexical/private dependencies, import replay, native versus ordinary conformance, associated type inference, inheritance, positive/negative cache keys, generated-owner collisions, wrapper binding, update/discard helpers, ABI aliases, descriptor thunks and registration, protocol/adoption parsing. | No full visibility/cache replay matrix rerun; no integrated native projection rewrite, inheritance-width stress or descriptor failure probe. Keep source occurrence, conformance and generation decisions separate. |
| [src/transform.x](../../src/transform.x) | 4968 | All source; typed callback and checked Func readers, direct/indirect/context and inline bridges, lambda cells/snapshots/capture environments, cleanup labels/goto/volatile roots, static initializer classification, try/defer lowering, printf Var boundary, call/declaration/destructuring conversions, indexed/protocol operations, literals/segments, local normalizer and generated sibling drain. | Source-only signature and return-cleanup proposals. No full typed callback, volatile/static/goto/printf/destructuring matrix rerun. Existing cast and metadata stage boundaries retained. |
| [src/regions.x](../../src/regions.x) | 1398 | All source; runtime effects versus result ownership, expression projections, lexical region/fact and borrowed place identity, two-owner flows, parameter sinks, worklist ordering, frees/moves, restored writes/defer lifetimes, blocks and path limitations, per-unit fixed point, ordinary warnings/meta errors/audit consumers. | No whole region rewrite, project certify run, raw C/callback provenance extension or scratch-scope ownership proof. The existing diagnostic limitations remain explicit. |
| [src/builtins.x](../../src/builtins.x) | 1022 | All source; scope macro, typed cursor versus Iter foreach selection and outputs, class Shape/defaults/new/init/refusal/drop/boxing/equal/hash/writers/render paths, native Lisp group records and target registration. | Source-only constructor argument accumulation candidate; no rewritten class generator, broad class/layout/refusal/cycle corpus rerun. Lisp binding and class builder name validation differences retained. |
| [src/adapter-memo.x](../../src/adapter-memo.x) | 9 | All source; one conditional create-and-publish operation for named adapter keys in the Compiler's existing names owner. Creation precedes cache publication; hit reuses the canonical value. | Keep the delivered macro; no new generic cache/transaction framework. |

## Compiler parser and backend

14 files, 16,853 inventory lines.

| File | Lines | Operations reviewed | Gap or retained boundary |
| --- | ---: | --- | --- |
| [src/ast.x](../../src/ast.x) | 300 | Canonical binding projections, recursive child rewrite, source constructors, initializers/prototypes, statement placement/terminating behavior, iterative generic head search and preprocessor-arm helpers. | No complete candidate or branch matrix. |
| [src/cache.x](../../src/cache.x) | 805 | Literal materialization, static-array initializer assignment, constant qualification, dependency queue/cycle diagnostics, cache key split, iterative DAG residency, TU-local header and source initialization. Retain separate residency and declaration order. | No complete candidate or branch matrix. |
| [src/collect.x](../../src/collect.x) | 1182 | Entire process-cache retention, prelude cold/replay, segmented file/include walk, shallow child state merge, package surface visibility/prefixing/import replay, interface candidate/read/identity/dependencies/datum serialization, binding renumber and cache lifecycle. | No complete candidate or branch matrix. |
| [src/deps.x](../../src/deps.x) | 137 | Atomic publication, sorted prerequisites, default/custom targets, phony output, Make word escaping, first-rule prerequisite parsing; colon restriction mismatch is unprobed. | Delimiter mismatch was independently reproduced and repaired in the accompanying mitigation; no second unresolved finding. |
| [src/diagnostics.x](../../src/diagnostics.x) | 504 | Positioned records, holds/releases, filtered limit notices, human/JSON output, labels/source context, deferred/immediate printing and counts; native partial-write behavior not injected. | No complete candidate or branch matrix. |
| [src/emit.x](../../src/emit.x) | 1431 | Whole lowered grammar dispatch, declarator folding, types/params, function/static state, literals/collections, expressions/control/native calls, iterative left operator spines, origin markers, directives and aggregate lowering. Full fallback/precedence trace; no full candidate proof. | No complete candidate or branch matrix. |
| [src/expressions.x](../../src/expressions.x) | 4952 | C precedence, postfix receiver/delegate/completion lookup, calls/Func carrier preparation, conversion warnings, protocol/discard selection, identifier binding/capture, resolver dispatch, literal promotion, native initializer rows/layout/adapters, speculative conversion and final target conversion order. Retain semantic continuations and native ICE/layout ownership. | No complete candidate or branch matrix. |
| [src/format.x](../../src/format.x) | 211 | Entire Pretty token scan, directive/ordinary formatting, indentation, mapped newlines, generated/source line accounting and origin-aware token output. | No complete candidate or branch matrix. |
| [src/generate.x](../../src/generate.x) | 1397 | Complete partition/publication operation, typedef promotion/forwards, conditional groups, public object/function placement, file-init/guards/shutdown, cache reachability, native #undef body movement, declaration dependencies, C/H generation, definition/interface/dump rows. Existing decorator reuse proposal. | No complete candidate or branch matrix. |
| [src/grammar.x](../../src/grammar.x) | 224 | Shared source macro content projections, fixed source patterns, canonical expression/block/literal/slice/composite/call forms; stage and semantic operations stay separate. | No complete candidate or branch matrix. |
| [src/literals.x](../../src/literals.x) | 1483 | List/Array/Map/String/SymbolSet production and quoting, newline/interpolation normalization, native perfect-hash generation, lambda parse/bind/capture state, exact Symbol/binder/number rules. Executed bounded SymbolSet extraction. | No complete candidate or branch matrix. |
| [src/parse.x](../../src/parse.x) | 3337 | Top-level dispatch, meta/class/protocol declarations, keyword aliases, specifier/declarator/params, parsed and constructed binding, source definitions, pragma/package surfaces, source positions. Full declarator producer trace; no recovery redesign. | No complete candidate or branch matrix. |
| [src/sourceview.x](../../src/sourceview.x) | 74 | Overlay canonical path identity, source existence/read, sticky changed paths, disk fallback and query boundaries. | No complete candidate or branch matrix. |
| [src/statements.x](../../src/statements.x) | 816 | Parsed and constructed control flow, optional-ref presence, return/goto/with, Match cases, try/catch/defer syntax and scope-aware statement binding. Keep cleanup lowering downstream. | No complete candidate or branch matrix. |

## Library values, lisp and match

43 files, 21,034 inventory lines.

| File | Lines | Operations reviewed | Gap or retained boundary |
| --- | ---: | --- | --- |
| [lib/var.x](../../lib/var.x) | 1291 | encoding, constructors, registry/direct and overflow object dispatch, equality/identity, wide boxes, native readers | Keep exact tag/pointer/wide identities; numeric consumer proposal P4; enum projection remains unproved |
| [lib/varconvert.x](../../lib/varconvert.x) | 289 | fifteen-family decode/metadata; checked float-to-int and modular int conversion; target casts | One decoded-to-native owner P4; no numeric record ABI merge |
| [lib/varops.x](../../lib/varops.x) | 583 | fast i32/f64 paths; promotion; shifts/overflow policy; general floating reboxing; truth | Delete promotion intermediate P4; full family parity and timing unrun |
| [lib/varops.x](../../lib/varops.x) | 79 | operator row/template projection and update routing | Small shared policy owner already; no new generic operator framework |
| [lib/var-ledger.x](../../lib/var-ledger.x) | 24 | generated table invocations from tag ledger | One tag projection owner already; no independent duplicate table removal |
| [lib/var-tags.x](../../lib/var-tags.x) | 414 | ledger rows and AST projections: descriptors, unbox, numeric, IDs/checks | TagId redundancy candidate unproved due declaration collection/bootstrap |
| [lib/common.x](../../lib/common.x) | 31 | checked numeric unbox readers projected from native scalar ledger | Keep numeric conversion owner, do not substitute raw decode |
| [lib/iter.x](../../lib/iter.x) | 23 | fixed signature adapters from source scalar types | Generated native boundary intentional; no blanket wrapper deletion |
| [lib/native-scalar-types.x](../../lib/native-scalar-types.x) | 92 | native names, widths, Var tag/read/box ledger | Existing fact owner; platform width must remain native |
| [lib/integer-ops.x](../../lib/integer-ops.x) | 45 | native integer update policy, bit arithmetic and shifts | TypedMap modular policy differs native typedArray C operations; retain distinction |
| [lib/datum.x](../../lib/datum.x) | 264 | write/read tagged values, nested containers, frame protocol and result rejection | decode-list scratch candidate P2 follow-up; malformed/cycle corpus not executed |
| [lib/string.x](../../lib/string.x) | 1842 | all constructors, Pool ownership, byte operations, replace/slice/join, callbacks, format, escapes, conversions and cursors | find-all/render scratch and Symbol roundtrip follow-ups; callback construction guards already present |
| [lib/string-classify.x](../../lib/string-classify.x) | 98 | byte classification and whole-string predicates | Locale/byte policy explicit; no duplicate-owner deletion established |
| [lib/string-number.x](../../lib/string-number.x) | 98 | checked number parsing and native formatting conversions | Parse vs scan distinction intentional; no alternate parser consolidation proposed |
| [lib/list.x](../../lib/list.x) | 1037 | canonical cells, ownership, builders, selectors, functional loops, conversions, sorts and iteration | List.array producer guard then sort copy-walk deletion; shared kernels already |
| [lib/list-selectors.x](../../lib/list-selectors.x) | 113 | optional compound selector projections and receiver behavior | Optional surface intentional, not obsolete aliases without caller inventory |
| [lib/typed-list.x](../../lib/typed-list.x) | 102 | typed List view helpers/methods and value transforms | Zero-copy validated view differs packed arrays; keep |
| [lib/array.x](../../lib/array.x) | 455 | Var-array instantiations, functional and heap operations, observers/exports | Producer and managed-render follow-ups; no wholesale typed-family replay |
| [lib/array-generics.x](../../lib/array-generics.x) | 912 | all shared storage mutation/copy/slice/sort/observe/typed publish/update/iterate kernels | Guarded typed publish is model P2; native bracket/update behavior deliberate |
| [lib/map.x](../../lib/map.x) | 226 | boxed Map instantiations, public observations, cycle-aware export staging | Rehash callback/cycle owner mandatory; render/result follow-ups |
| [lib/map-generics.x](../../lib/map-generics.x) | 930 | Robin Hood insertion/backshift/growth, facade policies, observe/iterate/typed convert/export/box | P2 proved; setindex and insertion-tail cleanup source-only; staged growth already guarded |
| [lib/typed-array.x](../../lib/typed-array.x) | 205 | all native family instantiations, comparators, exports and literal meta prototypes | Literal meta prototypes/shallow collection boundary retained; guards already present |
| [lib/typed-list.x](../../lib/typed-list.x) | 123 | all view families and conversion/iteration publication | Typed storage/identity deliberate; wide element limitations remain |
| [lib/typed-map.x](../../lib/typed-map.x) | 402 | four native key/value families, hashing, width/update policies, staged exports | P2 owns shared conversion; no native policy unification |
| [lib/iter.x](../../lib/iter.x) | 890 | cursor lifecycle, fluent/Func callbacks, map/filter/scan/zip/unzip/unique/chain/reductions | P3 remove discarded prefix; whole Unzip rewrite not run |
| [lib/protocols.x](../../lib/protocols.x) | 85 | concrete lifecycle, iteration and Var protocol declarations | No second representation; generic protocol cleanup must respect borrowed returns |
| [lib/lib.x](../../lib/lib.x) | 93 | DisjointSet find/union/roots/sizes and observers | Sizes Array finish-only candidate; no rank/parent derived-state deletion proved |
| [lib/lisp.x](../../lib/lisp.x) | 2161 | session lifecycle, recursive/tail evaluator, special identities, capture/lookup, native bridges, budgets/interrupt, reader and API | P6 separate semantics; accepted capture/limit/adoption/reader work already root candidate |
| [lib/lisp-init.x](../../lib/lisp-init.x) | 163 | native standard binder/signature/construction algorithms and registration adapters | Prior flat binder/let repairs done; no duplicate old proposal |
| [lib/lisp-targets.x](../../lib/lisp-targets.x) | 35 | optional native binding rows/filter boundary | Target isolation purposeful; no reintroducing optional packages into prelude |
| [lib/context.x](../../lib/context.x) | 365 | complete open rollback/close ordering, built-in graph export, cycles and custom hooks | Keep move-identity-before-walk/Map rehash; generic transfer collapse unsupported |
| [lib/func.x](../../lib/func.x) | 426 | signature construction, copied native contexts, adapters, arity/reference/return checks | Native crossing checks protect hand-written adapters; no blanket redundant-check deletion |
| [lib/match.x](../../lib/match.x) | 2777 | all grammar/normalization/layout/lowering/execution/search/template/cache/site/shutdown paths | P1 and P5; two replacement lookup policies differ; no direct-map cache rollback |
| [lib/match-machine.x](../../lib/match-machine.x) | 526 | all opcode execution, undo/span/relation/materialization/lifecycle | Relation scratch early return candidate unprobed; public finish running refusal deliberate |
| [lib/machine.x](../../lib/machine.x) | 471 | instruction/builder/program/view/decoder and capacity ownership | Match-only current architecture; no Lisp machine reinvention |
| [lib/meta.x](../../lib/meta.x) | 1040 | all syntax/type/source/literal/statement/function/macro construction helpers and compiler-only declarations | Ordinary AST values; scratch request lifetime needs complete caller audit; no blanket map callbacks |
| [lib/scripting.x](../../lib/scripting.x) | 18 | script-unit optional-module include owner | Small explicit composition; no core prelude expansion |
| [lib/scan.x](../../lib/scan.x) | 693 | all status scanners, numbers/suffixes, C/x2c escapes, atoms/symbols, byte positions | Allocation-free recognition vs conversion intentionally separate |
| [lib/tokenizer.x](../../lib/tokenizer.x) | 967 | all token/mode/position output, operand context, layout line/edit/emission and lifecycle | Layout constructor allocation guard source-only; meaningful full operation, no arena arithmetic mandate |
| [lib/symbol.x](../../lib/symbol.x) | 281 | 5/7-bit encodings, exact try_new, decode/format/parse and conversions | Stack roundtrip proposal source-only; do not change folding/truncation or zero-decode contract |
| [lib/symbolset.x](../../lib/symbolset.x) | 130 | packed immutable literal storage, membership/index/traversal | Single immutable representation; arbitrary set replacement not proposed |
| [lib/atom.x](../../lib/atom.x) | 230 | short exact and long canonical name construction, promotion, strings/repr/iteration | Symbol vs Atom semantics deliberate; managed-repr follow-up |
| [lib/private-keywords.x](../../lib/private-keywords.x) | 5 | single __ guard for private embedded translation keyword | Tiny syntax boundary; no alternate metadata owner needed |

## Library lifetimes, io and threads

28 files, 12,324 inventory lines.

| File | Lines | Operations reviewed | Gap or retained boundary |
| --- | ---: | --- | --- |
| [lib/scope.x](../../lib/scope.x) | 1073 | Intrusive links, aligned prefix, realloc/move, finalizers, shutdown/thread owner, stats | scope suite; Job finalizer probe; native allocation-failure paths not injected |
| [lib/block.x](../../lib/block.x) | 331 | Stable handle/backptr, capacity/growth, borrowed Bytes, release/move/export operations | Exercised through Buffer/File/Regex; independent block suite not run here |
| [lib/pool.x](../../lib/pool.x) | 1000 | Intern hit/discard, bitmap/slots/depot registry, promotion, parent release, locks and current/thread lifetime | pool/thread suites; Args allocation probe; mutex-init/atomic proposals not patched |
| [lib/buffer.x](../../lib/buffer.x) | 357 | Text/line Blocks, alias growth, indents/status, formatting, canonical consumption, ownership | buffer suite; JSON and Regex probes; source proposal not built |
| [lib/error.x](../../lib/error.x) | 1401 | Record regions, snapshot copying, visible/hidden/running handlers, capture/retain/landing/reset/pop/shutdown | error/exception/thread/logger suites; custom callback full fault matrix not run |
| [lib/error_init.x](../../lib/error_init.x) | 27 | Separate startup wrapper avoids automatic emitter-facing initialization | Startup through all probes; boundary retained; preinit subprocess fixture not rerun |
| [lib/error-private.x](../../lib/error-private.x) | 27 | Complete generated private record/view/handler storage shapes | error suite; fields traced to consumers; not flattened |
| [lib/error-macros.x](../../lib/error-macros.x) | 41 | Complete nonreturning ledger and custom fallback decorator | error/exception suites; ledger/return distinction retained |
| [lib/exception.x](../../lib/exception.x) | 267 | Frame state, cleanup draining, cleanup-error dominance, longjmp/landing restoration, floors/shutdown | exception/error suites; no standalone fatal-subprocess matrix rerun |
| [lib/diff.x](../../lib/diff.x) | 243 | Bounded edit frontier/backtrack, operation generation, unified hunk rendering, scratch lifetimes | three diff tests pass; existing scratch repair acknowledged, not rediscovered as new |
| [lib/digest.x](../../lib/digest.x) | 130 | Full SHA-256 block/padding/ring arithmetic, raw File streaming/errors and String wrappers | digest suite/NIST vectors; no additional cryptographic certification claimed |
| [lib/json.x](../../lib/json.x) | 570 | Ordinary value encoding/parse, UTF-8/surrogates, depth/numbers, optional decoder scratch and render cycle handling | JSON suite; rejected-string retention probe; partial container transactions not redesigned |
| [lib/file.x](../../lib/file.x) | 596 | Native/status operations, owned/borrowed streams, regular/nonregular text, growth/NUL, raw iteration, close-on-transfer | file suite; Job probe; Linux fopencookie-specific branches not available on this macOS |
| [lib/path.x](../../lib/path.x) | 559 | Normalization/join, glob/walk, copy/symlink/source protection, recursive remove, native DIR lifetimes | Path suite; source-confirmed release gaps; fault injection not performed |
| [lib/process.x](../../lib/process.x) | 618 | argv/env launch staging, pipe descriptor owners, child native crossing, reap/status/results/options/cleanup/finalizer | Process suite and native descriptor/reaped-child probe; other OS/fork fault matrices not expanded |
| [lib/regex.x](../../lib/regex.x) | 823 | Parser/node classes, byte sets, capture Lists, continuation/backtracking/depth, search/empty progress, replacement/split | Regex suite plus temporary direct traversal parity/allocation probe; no full alternate-engine equivalence |
| [lib/logger.x](../../lib/logger.x) | 860 | Levels/policies, serialized callbacks, field retention, sinks, recursive traversal/pool export and global lifecycle | Logger/error/thread suites; synchronous borrowed-state contract retained |
| [lib/thread.x](../../lib/thread.x) | 338 | Input-copy alignment/overflow, active worker ledger, policy sealing, native join/export failure/free/shutdown | Thread suite; no sanitizer/C memory-model proof |
| [lib/thread-state.x](../../lib/thread-state.x) | 32 | Full thread-local render/exception state allocation and native release | Indirect Thread/Exception suite coverage; preinit-native malloc failure not injected |
| [lib/mutex.x](../../lib/mutex.x) | 139 | Throwing owned Mutex and separate native fatal recursive helpers | Thread/shared-state and Pool tests; independent mutex suite not run here |
| [lib/dispatch.x](../../lib/dispatch.x) | 942 | Descriptor selection, rendering recursion, primitive String/Buffer paths, equality/order/truth/iteration/member/index adapters | Indirect collection/error/json/logger tests; complete primitive format/performance corpus not run |
| [lib/common.x](../../lib/common.x) | 906 | Var ABI/tag assertions/aliases/callback rows, native scalar readers and startup/index boundaries | Compiled by all tests; ABI left unchanged; cross-platform ABI assumptions not independently proven |
| [lib/args.x](../../lib/args.x) | 312 | Complete spec/property reader, long/short parsing, repeated/default/operand/required rules, usage formatting | Args suite and n=50/100/200 Pool allocation probe; proposed scratch owner not implemented |
| [lib/split.x](../../lib/split.x) | 283 | Eager split/join and borrowed stateful split/word/line cursors, next/out parameter behavior | seven split tests; borrowed source lifetime preserved |
| [lib/clibc.x](../../lib/clibc.x) | 27 | All current compile-time C scalar/string declarations | Parsed through baseline library; each individual C call not reprobed |
| [lib/cmath.x](../../lib/cmath.x) | 129 | All native math meta declarations including pointer-out functions | Declaration surface read; no full numeric-domain/native-symbol sweep |
| [lib/static-init.x](../../lib/static-init.x) | 147 | Acquire/retry storage, ready publication, wait/owner cycle, commit/abort and thread/process shutdown | Source coverage; runtime compiler statics exercised indirectly; static-init suite not run separately |
| [lib/system-macros.x](../../lib/system-macros.x) | 146 | Complete dedent/fold boundary, case grouping/transfer, source locations, assert/todo/unreachable/time decorators | Six-case actual dedent parity; other macro suite not run separately here |

## Other requested areas and limits

The original independent review also covered root/stage/bootstrap/configure/
release/editor/doc tooling, all eleven optional package layouts/pins/contracts/
representative examples, harnesses/manifests and architecture/language/library
book sections. Coverage is extensive rather than uniform line/path certification
outside the direct source inventory. No release publication, device-backed UI,
Torch/operator/C* backend completeness or every-host matrix is claimed.

Focused new compiler SymbolSet and region proofs are exact extracted operation
or kernel controls. They do not establish integrated compiler memory/performance
improvements. Macro/main/declarator/metadata candidates remain source-only;
full numeric/declarator, fault/race/sanitizer, cold-interface/SDK/custom-export
and platform matrices remain explicit gaps. The plan distinguishes caller
semantics and representation decisions from compatible source cleanup.

The integrated mitigation was checked separately with 919 units/20,432 assertions,
906 compiler fixtures across the suite and focused normal-host-IO rerun,
60 curated examples (56 run/4 build-only),368 book samples/87 matching outputs,
self-host stages 1/2 identical 192 C/H files, and full autodiff 16 tests/94 assertions,
nine fixtures/19 artifacts and both examples. Runtime units preceded the later
compiler-only bound-carrier repair; fixtures/self-host/book/examples followed
it. PCRE2 20/118,yyjson 27/149, BLIS 16/202 passed; yyjson native instrumentation
allocated/released 12 documents with none outstanding. The PR's publication
gate result is reported separately from these earlier local checks.

Libuv remains limited: 74 existing tests/818 assertions and actual/injected
run/entry/resume/close error controls pass, but native directory callbacks
independently report EMFILE(-24). Positive directory delivery and its cause
remain unresolved. No host explanation is inferred from that observation.

The prior historical beautification closing before/after audit is not silently
marked complete by this independent current-tree inventory. No new recurring
gate, benchmark requirement or readiness expansion is proposed.
