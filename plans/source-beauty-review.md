# Independent x2c source review

> Status: reference - 2026-09-29.
> Reviewed tree: `247b7fbe59198517a86a3d1f041448f0c9d30f90`.
> Original evidence for [source-beauty-execution](source-beauty-execution.md).
> This is a frozen review, not the implementation status.

Yes. x2c can become a more beautiful example of itself by preserving the
semantic information it already has and giving repeated decisions one owner.
The strongest opportunities are connected changes to binding, typing,
constructed syntax, and sequence construction. Another broad syntax cleanup
would do less for the language than these changes.

Reviewed tree: `247b7fbe59198517a86a3d1f041448f0c9d30f90`.
This was a read-only review of tracked files. No implementation, commit,
fetch, push, or publication validation was performed.

## Independence and scope

The initial impression reproduced below was recorded before opening
plans or git history. The original first-impression/probe files remain ignored
local evidence; the complete findings and implementation decisions are saved
in this reference and its execution plan. Three independent component reviews
covered the compiler
frontend, backend/tooling, and runtime; package, documentation, example, and
integration review supplied the wider context. The first assessment came from
current code and executable probes, using the repository's current language
book and agent guidance. Later reading of selected plans and commit subjects
qualified recommendations without replacing that initial judgment.

The authored inventory contains 34 compiler files and 68 runtime files,
approximately 67,000 physical lines before packages, examples, tests, and tools.
Every compiler/runtime owner received a structure survey. The frontend reviewer
read all twelve assigned source files line by line. Detailed runtime/backend
passes followed the major semantic and lifetime owners; these are extensive
reads, not a claim that every line of every peripheral tool or test was audited.
Generated `lib/x2c.x`, bootstrap C/H, and Torch operators were assessed through
their authoritative owners rather than treated as authored cleanup targets.

## What already makes the source beautiful

The best parts show the language's semantic operations directly:

- [Shared return finishing](../src/statements.x), function finishing in
  `parse.x:1429`, and `Type.declaration_parts` in `type.x:57` make construction
  read like the operation it implements.
- `expressions.x:1821` exposes the expression grammar through structural Match.
  Immutable fixed-point transformation followed by a separate cleanup pass
  keeps rewriting and lifetime work understandable.
- Lambda and region analysis retain binding identity. Literal templates make
  emitted AST shapes visible instead of hiding them behind procedural builders.
- Shared collection families and the canonical Var tag ledger remove genuine
  repetition while retaining deliberate native arithmetic differences.
- Context export walks a List's spine iteratively and recurses into its values.
  Diff's prepend-and-reverse builder is already a brief linear algorithm.
- The build pipeline shares `CliRequest`, `Build`, and `Toolchain`; the editor
  asks the compiler for semantics and uses JavaScript for transport and offsets.
  `tools/gen-package-index.x` is a useful example of real x2c scripting.

Preserve canonical List identity and suffix sharing, source/evaluation order,
explicit ownership, transactions, and native ABI boundaries. Initializer
cursor/ordinal rules, inferred native array dimensions, speculative conversion
rollback, Pool promotion and allocation outside locks, and native callback
cleanup all earn their complexity. A new universal copier, eager macro pass,
or parser framework would need to delete more complexity than it introduces.

## Highest-value connected changes

### 1. Preserve complete Types and binding identities

The small callback adapter is the clearest concrete example.
`src/lambda.x:884-905` partially decodes a function Type, retains its first return
component, and discards the rest. An `unsigned long` callback becomes
`unsigned int`. The same file already has `_typed_function_parts` at line 69,
which preserves the complete Type.

A prospective replacement can use that owner directly:

```x2c
List raw_params = NULL;
Type return_type = NULL;
if (!_typed_function_parts(expected_type, &raw_params, &return_type))
  return argument;
```

This is a design sketch, not an implemented or validated patch. Retain the
existing variadic/callback policy and cover pointer, reference, and closure
forms. The resulting code can be shorter and correct for more of x2c's own
Types without adding a representation.

`src/cleanup.x:396-458` takes a different lossy shortcut: changed locals and
pointer holders become String names. Qualification at lines490-535 then
applies one binding's facts to unrelated shadowed bindings. Keep the designated
binding throughout the existing analysis. Extend the current designation
helpers if needed; label spelling has separate scope rules and should retain
its own treatment.

Numeric crossings belong in the same ownership review. `sizeof` is recorded
as `(unsigned)` in `expressions.x:598-617`, so boxing selects a 32-bit Var family
on this 64-bit host. Lisp integer lifting at `macros.x:1211` and
`x2c.literal.int` at `etc/compiler-sdk.xlisp:15` stamp `(int)` independently of
range. Source literals already have native-family selection in
`Type.numeric_literal`. Establish a shared numeric construction policy that
preserves the value and target Type. Signed minima, unsigned values, and
validated token spellings need deliberate treatment; simply passing every
Lisp `str` to the token-oriented helper would be incorrect.

### 2. Make source and constructed syntax share semantic sequencing

Source `try` processes body, catches, and cleanup in source order;
`bind_syntax` processes catches and cleanup before body. Source `match`
processes subject before arms; constructed `match` reverses that order.
Compile-time effects expose both differences.

`src/parse.x:2415` and `:2427` and `src/statements.x:392` and `:449` should agree
on scope creation, child binding order, binder introduction, and canonical
output. Existing `finish_return_statement`, `begin_match_arm`,
`begin_catch_arm`, and function finishing are the right level of shared owner.
Start by correcting ordering, then share the actual semantic steps where that
removes duplication. Do not rebind already bound token results or add a generic
callback interpreter merely to make the traversals look similar.

This improvement directly serves the meta-language goal: a macro should be
able to construct an ordinary canonical List and get the same semantics as
the corresponding source. Origin tracking or extra authentication would work
against the deliberate language contract.

### 3. Make the SDK's operations compose, then finish the AST grammar family

The documented `x2c.decl.make` name operand is a value from `x2c.ident`.
`etc/compiler-sdk.xlisp:50-58` wraps that tagged name again. The String-name
control builds successfully; the documented composition aborts the compiler.
Keep the canonical name operand directly, with compatibility for current
String callers. `x2c.param.make` has the same source construction, but only
`decl.make` was executed in this review.

Next, express the declaration/type family with named Match captures.
`src/type.x:909-1021` combines a tag switch, positional selectors, shape tests,
and modifier interpretation; `Sym.declare_field_order` at `compiler.x:3345`
and `_lower_self_declaration` at `parse.x:173` repeat parts of the grammar.
Reuse `Type.declaration_parts`, `parameter_ast`, and `declaration_ast` for
construction. Preserve the modifier algorithm and native/aggregate semantics.
The reason for this work is readability and one visible grammar; a speculative
typedef-name collision was withdrawn after checking String/Symbol behavior.

Receiver-relative signature substitution is another small connected family:
`expressions.x:309` and `protocol.x:675` retrieve the same semantic fact through
spelling and binding maps. One substitution owner can accept binding,
signature, and receiver while leaving distinct lookup policies with their
current callers.

### 4. Use immutable Lists for published values and suitable temporary builders

Repeated singleton `List.append` copies every left prefix. With 1,000 distinct
integers, the focused probe retained 500,500 new canonical cells; an Array
followed by `list_free()` retained 1,000. Final length and contents agreed.

The source-backed candidates are repeated argument accumulation in
`lib/args.x:129`, capture-name accumulation in `lib/regex.x:225`, and generated
Torch result builders in `packages/torch/tools/gen-ops.py:715-734`. Preserve
ordering, defaults, public List results, and cleanup around native handles.
Fixed-size AST append and Diff's cons/reverse builder do not have this
quadratic behavior. The probe demonstrates the construction algorithm; it
is not a benchmark of completed replacements in those modules.

Compile-time Lisp already supplies a particularly direct improvement:
`ad._concat` at `lib/autodiff.xmacro:202` uses `(foldl append '() lists)`.
The shipped `(apply append lists)` idiom concatenates from the right and
avoids cloning cumulative prefixes. Its forward/exit accumulators at
lines 585-594 can also collect fragments and publish once, while keeping
reverse-control pruning unchanged. No new Lisp builder type is necessary.

At lifecycle crossings, iterate over flat List spines and recurse into heads.
The Error detail probe crashes at 200,000 integers; LLDB identifies repeated
`_copy_value` cdr frames. Context export at `lib/context.x:212` and prepared
Match walks already supply the pattern. Review Error snapshots
(`error.x:698`), Logger retention (`logger.x:538`), and Match normalization
(`match.x:323`) as a connected algorithm family. Only Error copying's crash
was reproduced. Preserve each owner's leaf policy: Error rejects identity
leaves, Logger borrows them, and Context can move them.

### 5. Delete specific duplicate representation and metadata owners

The array-family macros already emit seven `Self` declarations per family.
`lib/typed-array.x:172-226` repeats 49 literal declarations. In the isolated
fresh-name experiment, both versions build and run with identical seven
public native signatures. An alias chains all seven results into an
alias-only `.done()`, so imported `Self` metadata remains usable without the
literal rows. This strongly supports a narrow deletion; authoritative source
removal and relevant corpus/header checks have not been performed.

The historical declaration-discovery design explains a superficially similar
case that is different. Generated function definitions are skipped during
ordinary shallow binding before signature collection. Private converters in
`lib/iter.x:83-103` therefore still need their literal declarations before
protocol resolution. Sharing shallow signature collection for source and
generated definitions is a separate compiler proposal. Preserve selective
collection and deferred arbitrary Lisp evaluation.

Map growth manually derives Block backing allocations at
`lib/map-generics.xmacro:164-167`. `Block.move_to` already owns moving both the
stable handle and backing storage. Use `.block().move_to(&map.scope)` instead
of reproducing its layout. Keep both replacement arrays staged and the map
commit order intact.

The deeper pass found a second promising owner deletion: ErrorRegion allocates
separate String and List pools, while `Error.snapshot_in` and `since_in`
already use one supplied Pool for both. One region pool would remove a
second table/Scope/mutex owner per record or handler view. This is a
source-supported proposal; the whole-Error change has not been implemented or
tested. Preserve its separate wide-value Scope and admissibility policy.

### 6. Let compiler tooling use the compiler's source understanding

`tools/x2c_source.py` and `x2c_symbols.py` maintain substantial independent
syntax knowledge alongside canonical `.xi` type facts. The current scanner
finds three declarations in a tiny expression-bodied program using `<x>`.
Changing the Symbol literal to the legal `<(>` makes it find none, although
x2c compiles the program and prints `1 7`.

A bounded compiler-owned authored-declaration/documentation extraction path
would make source tooling follow the language it documents. Reuse tokenizer
comments and ordinary declaration boundaries. Current compiler facts retain
binder-name spans, not complete doc/declaration spans, so this is real work.
Define documentation adjacency, preserve UTF-8 byte spans and editor UTF-16
transport, macro order, visibility, and compact interfaces. Keep build-free
metrics and lexical audits independent of compiler availability.

The later scripting plan already identifies this keystone. The independent
review supports that direction with a current minimal reproduction; it does
not establish missing documentation in the current generated tree.

## Reproduced findings

The [probe sources](source-beauty-probes.md) are saved beside this report. Complete
build and failure logs are in `debug/source-review-*.log`. Retained generated
C and executables are under `/tmp/x2c-source-review`.

| Finding | Current observation | Owner / consequence |
| --- | --- | --- |
| Constructed control-flow order | Direct try: `(body catch finally)`; macro try: `(catch finally body)`. Direct match: `(subject arm)`; macro match: `(arm subject)`. | `parse.x:2415,2427` vs `statements.x:392,449`; compile-time behavior differs. |
| Callback return Type loss | Expected `unsigned long (*)(unsigned long)`; adapter emits `unsigned int(unsigned long)`. Native compilation fails. | `lambda.x:884`; complete return Type discarded. |
| sizeof boxing loss | Native `sizeof` is 4294967297; boxed value is 1. No large allocation is performed. | `expressions.x:598`; 64-bit native value crosses a 32-bit Var family. |
| Meta-integer boxing loss | Source literal boxes 4294967297; `$(begin 4294967297)` and `x2c.literal.int` both box 1. | `macros.x:1211`, SDK:15; meta-source stamps `int`. |
| Shadowed cleanup qualification | Writing outer `value` in try makes unrelated inner `int value` volatile; `_Generic` reports 1. | `cleanup.x:396,490`; spelling replaces binding identity. |
| SDK tagged-name composition | String-name declaration prints 42; same declaration using `x2c.ident` aborts, exit 134, unhandled `void-op` floor. | SDK:50; tagged name wrapped in another List. Only decl.make executed. |
| Flat Error-detail crash | 1,000 and 100,000 values reach catch; 200,000 SIGSEGV. LLDB repeats `_copy_value` cdr frames at stack exhaustion. | `error.x:568`; ordinary flat sequence consumes native stack. |
| Locale-sensitive JSON | Under `de_DE.UTF-8`, parsing `1.5` yields 1 and emitting 1.5 yields `1,5.0`. | `json.x:147,450`; JSON and process numeric locale disagree. |
| Lisp subject reevaluation | Side-effecting `match-case` subject runs twice after first clause misses. | `etc/init.xlisp:227`; subject binding is inside each clause. No explicit once-only book promise was assumed. |
| Duplicate empty dependency table | Two empty `[dependencies]` tables are accepted and the inert target builds. | `project.x:353`; Map content truth used as section-presence test. |
| Legal Symbol defeats doc scanner | `<x>` yields first/second/main; `<(>` yields no definitions. Original `<(>` program builds/runs. | `x2c_source.py:345`; literal parenthesis counted as syntax delimiter. No real-tree doc loss asserted. |

These observations justify repairing the specific owners. They do not imply
that whole subsystems are unsound or that every proposed refactor is validated.

## Lower-confidence proposals and deliberate limits

- Cleanup and emission both classify dynamic local-static initialization
  (`cleanup.x:269`, `emit.x:318`). A normalized per-binding decision could
  remove rediscovery. Keep native `__typeof__`, inferred extent/alignment,
  byte copying, guards, concurrent initialization, retry, thread-local storage,
  address identity, and protected control flow. Historical cleanup work
  deliberately separates these responsibilities; moving all of emission's
  logic into AST lowering is not established as simpler.
- Build header placement reparses generated C/H include text
  (`build.x:673`). Final emission include records might remove that seam,
  but source collection edges alone are insufficient. Cached workers,
  constructed includes, native preprocessing, and include precedence need a
  bounded experiment before recommending replacement. Do not infer includes
  from declaration filenames.
- BLIS's List-valued matrix/vector inputs are traversed by repeated positional
  indexing in validation and filling (`blis.x:166-206,270-298`). Sequential
  traversal should avoid quadratic List walks. Preserve prevalidation,
  admitted shapes, diagnostics, and native ownership; no adapter benchmark
  or replacement was performed.
- Libuv idle/prepare/check watchers repeat one family of mechanics while using
  distinct native types and event timing. A small Unit family may help, but
  a broad handle abstraction would obscure real lifecycle differences. No
  replacement prototype was attempted.
- Pool's ordinary `pool_multithreaded` int is written on every Thread.start
  (`pool.x:149`, `thread.x:246`) and read unsynchronized by existing workers.
  The first write precedes pthread_create; later starts have an apparent C
  read/write race. Source access patterns were independently checked, but
  no TSan or observable failure reproduction was performed. Retain the
  deliberate pre-worker fast path in any investigation.
- Func's five conversion catches may share a guarded capture. A capture used
  as an `!or` alternative would catch every code; it is not a valid shortcut.
  No consolidation was tested, so the existing handlers remain the evidence.
- The SDK literal-value reader accepts only `(int)` numeric forms today.
  Wide/suffixed/floating literal extraction was inspected but not executed;
  it is an open numeric-policy question, not another confirmed finding.

## Validation and coverage

All final checks below passed against the unchanged reviewed source tree:

| Check | Result |
| --- | --- |
| `make build-safe` | Safe stage 0 compiler/runtime rebuild succeeded. |
| `make verify` | 722 compiler fixtures  / 1693 artifacts; 925 main-suite tests  / 20347 assertions; 20 thread-suite tests  / 79 assertions; included boundary probes passed. |
| `make examples` | 59 passed: 55 run, 4 build-only; 60 classified. |
| `make packages-check` |All included package gates passed; 240 tests  / 2103 assertions. Cached dependencies used; headless graphics checks. |
| `make -C packages/sqlite test run run-lisp` | 15 tests  / 133 assertions and both ordinary/Lisp examples passed. SQLite is checked separately from root package target. |
| `make doc-check` |Documentation audit and derived llms files current. |
| `make doc-examples` | 338 samples compiled; 60 matching-output checks. |
| `make stage-2 stage-diff-1 stage-diff-2` |Stages 0/1/2 agree on 178 generated C/H files per comparison. |
| Site `npm test`, `npm run build` | 9 tests and full 9-page site/book build passed after installing the locked local dependencies. |
| `git diff --check`, worktree state |Clean tracked/untracked status; HEAD unchanged. Ignored notes/logs/builds remain. |

The package examples include an intentionally timed-out libuv job; its gate
succeeded. Early site testing without dependencies failed to import Astro;
locked dependency setup resolved it and the full checks passed. The Self
fixture's first native build used an absolute source include that implied a
nonexistent absolute generated header; using an ordinary x2c.x include made
both variants pass. Neither setup failure was treated as a repository defect.

Detailed coverage included frontend/AST/type/protocol/binding, immutable
lowering and native emission, compiler driver/build/project/toolchain,
collection/value/conversion owners, Error/Pool/Scope/Context/Logger, Lisp/Match
machines, autodiff, I/O/thread/process boundaries, all optional adapter
representations, package generators, current build/workflow/editor paths,
examples, tests, book semantics, documentation tools, and site integration.
Python tooling and test bodies were sampled rather than exhaustively audited.

Not attempted: stage 3 / portable bootstrap comparison, sanitizers/TSan, the
multi-platform/compiler matrix, interactive VS Code UI, actual window/audio
rendering, external C* installation/application behavior, release/install or
publication workflows, sustained package services, MNIST download/training,
and performance benchmarks of proposed replacements. Self fixture success
is not proof that deleting all 49 authoritative declarations preserves the
whole corpus. No proposed source change has been made.

## Recommended scope for subsequent implementation

First repair the existing Type/binding/order/name owners, with focused
reproductions for the behavior each owns. Then batch the sequence-builder and
flat-spine algorithms, narrow typed-array duplicate deletion, and Block
transfer cleanup. Follow with the declaration grammar family and shared
shallow signature collection if their source savings and corpus behavior
justify them. Compiler-owned authored-source facts are the strongest larger
meta-language project, already recognized by current planning.

The desired result is source where the canonical Type, binding, AST shape,
evaluation order, and lifetime are apparent at the point of use. Existing
verification targets are adequate for delivery; this review proposes no new
recurring gate, process requirement, or source-size quota.

## Frozen initial impression

```text
Independent first impression: x2c source beauty
Reviewed tree: 247b7fbe59198517a86a3d1f041448f0c9d30f90
Recorded before reading plans or git history. No tracked source changes.

Judgment
The compiler and runtime already demonstrate the language's strongest ideas:
canonical immutable Lists, visible input/output grammar, structural Match,
typed crossings, and cleanup beside acquisition. The best next improvement is
to give each semantic decision one owner and preserve the Type and binding
that owner establishes. Source size alone is not a useful target.

Positive examples
- Shared source/constructed return finishing in statements.x:158-170.
- Function finishing and lifecycle ownership in parse.x:1429-1495.
- Expression grammar dispatcher in expressions.x:1821-2190.
- Declaration reconstruction in type.x:57-76.
- Immutable fixed-point transformation followed by cleanup in
  transform.x:1779-1804.
- Binding-based lambda capture discovery in lambda.x:979-1007.
- Explicit deep operator traversal/native precedence in emit.x:1035-1158.
- Collection families generated from shared native algorithms.
- Context List export walks the spine and recurses into nested values.

Ranked source-based opportunities, before historical rationale
1. Share semantic control-flow sequencing between token parsing and
   constructed AST binding. Do not bind already bound token results again.
2. Carry complete canonical Types through callback adapters and native-value
   crossings. Reuse function-type decomposition instead of partial decoding.
3. Keep cleanup preservation keyed by binding identity rather than spelling.
4. Express forward sequence construction with Array and freeze once; loop over
   flat List spines rather than recursively visiting each cdr.
5. Finish the declaration/type grammar family with named Match captures,
   shared declaration reconstruction, and one SDK name representation.
6. Classify dynamic local static initialization once, with native spelling
   left in emission and lifetime/control-flow decisions made beforehand.
7. Investigate generated-method metadata: literal prototypes repeated after
   family generation may expose a compiler phase limitation. Test before
   recommending a language change or deleting the workaround.
8. Improve package generators/builders and sequential List consumers before
   expanding abstractions across dissimilar native lifetimes.

Reproduced at this tree during the independent pass
- Direct try compile-time effects: (body catch finally).
  Same macro-authored try: (catch finally body).
- Native sizeof of a 4294967297-byte array type is 4294967297; boxed Var is 1.
- Callback adapter for unsigned long return emits unsigned int and the native
  compiler rejects the function pointer.
- 1000-item repeated singleton append retains 500500 canonical List cells;
  forward Array construction and list_free retain 1000.
- Json.parse("1.5") in de_DE.UTF-8 parses 1; Var.json(1.5) emits 1,5.0.
- Lisp match-case evaluates a side-effecting subject twice after one miss.
- An empty duplicate [dependencies] manifest section is accepted.
- Error detail containing a flat List of 200000 integers crashes SIGSEGV;
  1000 and 100000 reach the matching catch. Stack cause still needs tracing.

Validation baseline
Safe stage-0 rebuild succeeded. make verify passed all compiler fixtures and
boundary probes and 925 unit tests with 20347 assertions, no failures/skips.
make examples passed 59 programs (55 run, 4 build-only), 60 classified.

Initial scope and unfinished inspection
Independent reviewers surveyed every compiler/runtime module's owner and
structure, with detailed reads of frontend/binding, AST/type/protocol, runtime
storage/values/lifetimes, backend/lowering, and native build/project owners.
Root inspected package representations, native callback/lifetime boundaries,
collection construction, examples, tests, and documentation ownership.
This freezes an opinion, not a claim of exhaustive line-by-line coverage.
Remaining detailed source reads include expression initializer lowering,
literal parsing, macro tail and compiler-state/token orchestration, specialized
emitter cases, CLI/help portions, and workflow/tooling/editor/site internals.
Package applications have not yet been executed; no release publication,
platform matrix, interactive GUI, sanitizer, or stage-convergence claim.

Preserve
List identity and suffix sharing; semantic/source/evaluation order; canonical
constructed Lists without origin authentication; binding/source identities;
rollback; native ABI and public compatibility; owner-specific copying and
transfer policies. Similar loops alone do not justify a universal copier or
replacing native storage algorithms with allocating collection operations.
```
