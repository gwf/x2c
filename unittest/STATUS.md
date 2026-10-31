# Status

## Optional example checks on 2026-10-30

The SymbolSet delimiter migration exposed existing failures that also reproduce
with the converged compiler at `b75c61da9`:

- `make examples`: `programs/tiny-lisp-min.x:2:110` reports "function takes
  1 argument, not 0" for `W()` with the `typedef void Z` parameter spelling.
- `make doc-examples`: the `language.md:106` sample declares `remainder` with
  a signature that conflicts with the C math function. The imports slide also
  requires a built PCRE2 package; that prerequisite is absent in these worktrees.

These checks remain optional. Their repairs are separate from the delimiter
migration; no expectations or sample classifications were weakened.

## Allocation accounting

Unit and compiler-fixture program runners enable `X2C_SCOPE_ACCOUNTING=1`
for their existing storage assertions. Scope lifecycle probes also check the
default disabled mode, explicit zero, initialization-time latching, scope
names, and finalizer cleanup. Default-off subprocesses clear the inherited
setting before startup; the probes do not change their parent's environment.

## Symbol-mode comparison scope

Module units support only default symbol collection. The optional raw-symbol
sweep classifies them as exclusions, and the conformance-mode comparison
checks flat runtime units. The stage and cold-collection comparisons cover
module units using their supported collection mode.

## Dual-macro migration follow-ups

The [migration tasks](../plans/archive/compiler-dual-macro-contract.md#migration-defect-tasks)
record the completed parameter-redeclaration and standalone raw-symbol
repairs. The depth fixture reaches a normal 64-level diagnostic; a truly
null-site invocation remains an unverified coverage gap, not a reproduced
crash. The capture-clause fixture checks reconstruction of value and reference
captures, expression and block bodies, and typed parameter sequences.

## Stage-1 thread region warning (resolved)

On 2026-10-21, `make build-safe stage-1` in an isolated clean archive of
`e2a78078edece1348abbbb7363c89560ae064706` fails while translating the runtime
with `--fatal-warnings`. `lib/thread.x:563` reports that the address of local
`run` can outlive its storage when stored through an unknown pointer.
The initial CLI implementation reproduced the same warning before any Thread
source edits. Its first publication attempt was blocked by this baseline
failure. Gary authorized CLI delivery despite the warning while a separate
repair proceeded. The upstream repair at `81a76f090` now replaces the local
coordination record with cleanup-owned storage and has been integrated here.
The normal publication gate passed on the combined tree at `27812dffe`;
warning policy is unchanged. See the
[CLI plan](../plans/archive/build-cli-defaults.md) for the retained verification
evidence.

## Reference Lisp diagnostic mismatch

On 2026-10-25, the optional `examples/programs/check-reference-lisp --build`
comparison agrees on 199 of 200 cases. The `lists` case passes `(car nil)`
to `list`: the runtime reports `(void-op (operation "apply") (index 0))`,
while the independent reference interpreter reports `(void-op)`.
The runtime produces the same diagnostic with the original `init.xlisp`
from `27dd8c6c2`, before standard-environment consolidation. Diagnostic
parity remains a separate follow-up; the expectations were not weakened.

## Coverage

- On 2026-10-24, `tools/indent-convert --check` exposed an existing call to
  `Tokenizer.new` without its required mode. The unchanged `9e68d6b` script
  reproduces the C arity error. The local Lisp-independence work supplies
  `<x2c>` while removing its reader-only evaluator session; conversion parity
  verification is recorded in the
  [local plan](../plans/archive/compiler-lisp-independence.md#local-result-and-evidence).

- Retired component experiments leave focused compiler fixtures for indexed
  rewrite entry points and rule order, independent rule composition, local
  binding recognition, runtime/meta Type operations, and Array alias adoption.
  Post-initialization fixtures cover mixed declarators, shared anonymous types,
  and cleanup when a later initializer raises.

- Native module probes reuse a constructor's cached Func across isolated
  units.
- `commands/repl/tests/run.sh` runs the REPL checks. `native-check.x` keeps
  globals, functions, records, and pointers live across native submissions,
  separates tag and object namespaces, completes fields and methods, and
  keeps a Func's reference capture across submissions. Rejected and failed
  submissions publish no names, and session close runs top-level cleanups
  in reverse order.
- `playground.py` creates, calls, and inspects C libraries from source,
  headers, and archives through the public command, including `:reset`,
  `:reload`, file-local statics, callbacks with userdata, and an optional
  host SQLite session. `terminal.py` covers candidate failure and
  cancellation, crash recovery as a transcript reset, cache pruning, exit
  hooks, saved-instruction replay, and terminal history. Both assert an
  empty per-run `TMPDIR`.
- `program.sh` resolves program addresses from sources, archives, shared
  libraries, manifest targets, and packages. It checks that `:reload` keeps
  one copy of each manifest root and that conflicting `main` roots and
  duplicate definitions fail.
- Linked extension probes build with parallel translation, so registration
  units collect package-prefixed declarations without a preceding unit cache.
- Lisp cases cover special-form rebinding after earlier effects or call
  arguments. Quasiquote cases retain operation selection, splice identity,
  and error/effect order. Tail-call cases check 100,000 iterations in
  constant stack.
- Automatic-differentiation cases compare forward loop initialization and
  step updates against finite differences, including comma clauses and
  `continue`. Tape cases cover inactive singular operations before and after
  the requested result and repeated reverse passes.
- Operator cleanup fixtures preserve borrowed named handles, returned
  temporary handles, and interior views while retaining cleanup for fresh
  operator chains. Header promotion covers secondary typedef declarators
  alongside opaque forward declarations.
  Generated protocol calls preserve native-to-Var conversion with cached,
  cold, and live symbol collection.
- Retained native-build probes cover changed include-search environments,
  newly shadowing headers, and `__has_include` without an include, plus
  unchanged object/archive reuse and installed prefixes below `builds`.
- The unit runner accepts optional exact suite-name arguments. Selection keeps
  registration order, runs duplicate names once, and reports unknown names
  with status 2. No arguments retain the full suite and validation behavior.
- Compiler phase fixtures cover focused token, AST, transform, emission,
  generated-file, diagnostic, and runtime behavior.
  Filtered symbol artifacts additionally own focused semantic Type values
  without copying the complete global table. `make verify-fixtures` checks
  expectations without rewriting them.
- AST declaration fixtures distinguish declarator `fnmod` from semantic
  Type `func`, use `(bindings ...)` for declarations and typedefs, and lock
  exact Types plus generated C across multi-declarators, function pointers,
  arrays, aggregates, methods, and initializers.
- Compiler-private AST tests own parsed, lowered, and generation phase
  legality; exact tag, arity, and field-role failures; explicit sibling
  sequences; and rejection of sequences in ordinary node fields. The
  declaration fixture additionally locks semantic function-pointer cast
  emission with a qualified pointer parameter.
- Sparse AST occurrence tests prove distinct source identity over interned
  nodes and generated ancestry through transform expansion. Binding fixtures
  prove stable declaration/reference identity, shadowing, capture retention,
  and fresh synthesized identities. Macro fixtures compare handwritten and
  generated forms while checking rollback after rejected syntax.
- The literal/cache fixture proves source-ordered raw Array/Map parse nodes,
  source-ordered boxed transforms, positional Array construction, and
  last-source-entry-wins Map replacement through cached native execution.
- The index/slice fixture distinguishes native indexing from Array, List,
  String, and Map helper lowering; proves transform-owned Map-key boxing,
  omitted/reverse bounds, and one evaluation of every side-effecting operand;
  and checks exact generated C and native results.
- Native array typedef indexing falls back to the resolved array element type
  after existing getindex lookup. Designated initializer coverage includes
  String/Var aliases, named-field continuation, nested arrays, sparse inferred
  bounds, struct/union elements, and safe discarded excess initializers.
- Qualified array typedef initialization converts direct String literals,
  including through several aliases and designators. `typedef-index-elements`
  runs String methods on the converted elements alongside explicit
  `String.new` elements.
- Adjacent C literal coverage preserves escape boundaries and String
  promotion. C static assertions work in file, block, aggregate-member, and
  canonical macro forms without consuming aggregate initializer slots.
- The Var-comparison fixture proves all eight comparison operators, native and
  mixed operands, wide value equality versus box identity, mutable object
  identity versus structural order, exact helper selection, and one evaluation
  of each side-effecting operand.
- The Var-alias fixture proves initialization, assignment, calls, returns,
  extraction, and every comparison family through direct and chained
  file-scope aliases while generated declarations retain their source names.
  A diagnostic fixture proves that block-local typedef declarations are
  rejected at the declaration token.
- The Var-numeric fixture proves dynamic binary lowering, Var-to-native
  conversion, short-circuit truthiness, addressable compound assignment,
  single lvalue evaluation, try/longjmp preservation, native-only behavior,
  and runtime results. The conversion fixture covers every native numeric
  target tag and extractor. The lvalue-boundary fixture covers every typed
  native compound adapter and volatile storage, while leaving `const` and
  `register` constraints visible in emitted C for the C compiler to own.
  Five diagnostic fixtures reject a statically nonnumeric peer, dynamic unary
  arithmetic, and helper-backed, enum, and bit-field compound targets. The
  fatal truthiness fixture proves that `void` is invalid rather than false.
- Two preprocessor process probes prove that source/include paths remain exact
  argv data, shell metacharacters cannot inject commands, and a host failure's
  stderr and status reach a structured x2c driver error. Compiler fixtures
  additionally prove inactive missing-include success and directive retention
  through compound-statement AST, generated C, and native execution. Active
  missing includes fail in native compilation or explicit preprocessing;
  translate-only preserves their directives.
- Exact fixtures prove one-based token positions, token-width diagnostic
  carets, rejection of unsupported `$()` and `@()` literal insertion forms,
  structured rejection of malformed braced forms, and transformed match/loop
  AST rendering. Empty native and boxed String representations are covered
  by the String and Var suites.
- Canonical scalar fixtures prove alternate legal specifier orders, promotion
  and mixed arithmetic, suffix-derived literal families, scalar typedef Var
  crossings, invalid combinations, and out-of-range integer-literal
  diagnostics.
- Native fixture programs compile with the active build flags. The
  defer/try fixture proves optimized preservation of directly modified locals,
  parameters, cleanup guards, rethrow state, and finalizers.
- Type-initializer fixtures prove the exact hook signature, one owner per
  translation unit, guarded cache ordering, non-static entry ownership,
  static-helper trust, direct-call idempotence, and structured rejection of
  unsupported `@init`.
- List and String canonicalization are covered directly: repeated and nested
  `cons` calls return identical cells, repeated `String.new` calls return the
  same interned String, and `String.intern_free` canonicalizes a separately
  allocated equal buffer. String tests additionally prove cached hash
  and length, transient/canonical freeing, bounded byte operations, empty
  search behavior, split/replace/partition utilities, and status-bearing
  numeric parsing.
- Empty Array and Map literals are covered as distinct allocated objects that
  can be mutated immediately. Boxing preserves their object identity, and the
  mutable-empty fixture proves that null pointers cannot be boxed under either
  mutable-container value tag.
- Runtime boundary regressions cover empty Block pops, Array reduction,
  String bounds/search/null ordering, short file reads, unsigned-character
  conversion, invalid hexadecimal escapes, descending ranges, and Symbol
  encoding/scanner boundaries. Block and Buffer coverage also proves
  checked growth, self-append, repeated fill, overlap handling, failure
  atomicity, text-only writes, embedded-NUL rejection, and multiline position
  state. Map tests cover growth, collision deletion, model churn, traversal,
  counted updates, and comparison laws. Runtime match tests cover typed-empty,
  fallback, normalized guards, star patterns, and status APIs. List tests
  cover 16-byte cells and iterative operations over 50,000 cells. Scope
  coverage additionally proves allocation-list updates, direct named-slot
  allocation, statistics, zero-size behavior, stack growth, and terminal
  shutdown diagnostics. Counted Array construction preserves raw Null and rejects dynamic `void` literal
  elements at the Array owner. Packed-container Context coverage proves
  typed Arrays and typed Maps through direct export and a
  nested Thread result, including pointer identity, aliases, canonical
  Strings, empty Strings, borrowed values, source close, later-bucket key
  collapse, recursive custom export, and subsequent growth.
- Var coverage proves registered source/tag round trips, exact wide scalar
  boxing, content semantics for wide boxes, typed custom dispatch, and
  explicit construction failures. Equality and identity inspect `void`; fatal
  probes prove that direct hash, ordering, and iteration still reject it.
  VarOps tests cover cross-tag numeric families, exact integer lanes,
  promotion, conversion failure, arithmetic, comparison, truthiness, and atomic compound
  updates. Iter and Map suites prove status-bearing control, raw Null Map
  traversal, and safe unsupported iteration. The `void` sentinel fixture proves
  List, Array, Map, and iterator value exclusion.
- Iter, Logger, File, and scanner suites own their direct runtime
  contracts, hot-path benchmarks, and boundary fixtures. The root `bm-all`
  target runs every focused benchmark owner.
- `TestHarness_run` fails on assertion failure, zero assertions, or
  unbalanced Scope state. Ambient errors remain with their configured policy
  owner. Tests return `void` and use bare `EXPECT_*` statements; the harness
  also provides `EXPECT_LIST_EQ`, `TEST_FAIL`, and explicit skipped tests.
- `test-match-binder.x` verifies that a matched String binds as a String.
- Match statement binders enter semantic arm scope as typed `Var` or
  `List` locals, definite assignment is enforced across guard operators, and
  dynamic-operator runtime cases are active.
- The repository-stabilization fixtures prove brace-free Match parsing and
  valid per-binding volatile emission when a non-leading destructured local
  changes across `try`. Compiler-private AST tests reject operator nodes beyond
  the emitter-owned unary, binary, and ternary forms.
- The Var suite cross-checks `Var.kind` against the tag definitions and
  covers `Var.clone_wide`; the typed-array suite covers raise paths, with
  `push` on a null array classified as the family
  `bad-arg` diagnostic; `test-symbolset.x` and `test-protocols.x` suites
  own SymbolSet runtime behavior and the base-default/descriptor-dispatch
  seams behind protocol adoption. A fixture locks `@(...)` inside `%""` as
  literal segment text; List-context rejection has its own fixture.

The 2026-10-05 publication probes found that exporting the Make help script
to unrelated child processes caused `var-chain-stack` to fail at its 256 KiB
stack limit. The export now belongs only to `help`. The unchanged fixture
passed six repeated nested-Make probes, and help output remains byte-identical.

## Native gaps after compile-time Lisp removal

- `meta-func-calls` no longer checks a lambda written as constructed
  `(expr ("Func") (lambda ...))` syntax reaching meta-body destinations.
  The removed `$constructed()` macro returned that syntax from a `$(quote
  ...)` form. The native form `macro Expression $constructed() =>
  $constructed_syntax();` expands inside each meta body to an ordinary call,
  as the language reference documents for `$f(x)` in a `meta` body. The meta
  helper then rejects the call: "cannot convert ("List") to ("Func")". No
  macro template form was found that spells that canonical AST; a `$(...)`
  body is rejected with "expected macro name after '$'". The five `built-*`
  rows were therefore removed. Ordinary lambda destinations remain covered.
- The project meta build writes a unit's meta group from an incomplete
  parse. A template slot that calls a project meta function, such as
  `@one_item($target)` in `macro Unit $through_sequence(Unit $target)`, is
  left for the translation, and the meta build's parse skips the whole
  form. Definitions after that form may name what it declares, so the group
  roots none of them: it keeps a later variable only when a meta function
  reaches it, and a later function only as its prototype unless one does.
  An unreached function whose result type names such a declaration gets no
  prototype. `macro-computed-slots` covers an untyped helper, an untyped
  global, a global initialized from the declaration, and a public function
  that reads it. A meta function that itself reaches such a definition
  still cannot run at compile time; C2 below would remove that limit:
  - C2: the meta build runs a same-unit `meta static` function by staging
    the group so far in process, as `bind_meta_group` does for a session.
    Nothing is deferred and the parse is complete. This depends on
    `X2C_NATIVE_MODULES` and changes the project meta build's design.

- `import-package-export-order` and its `packages/ordered/` sources were
  removed. They checked that package packs install in include-walk order by
  calling compile-time Lisp functions one package defined from another
  package's source, which relied on the shared Lisp session. A native meta
  function in one package does not see another package's meta functions
  from its own meta group ("call to undeclared function 'ordered_z'"), so
  the same ordering cannot be observed that way. Pack ordering itself is
  unchanged.

## Outstanding Items

### Constructed array-dimension macro

On 2026-10-28, `160828e5f` reproduces an unresolved macro in a constructed
array dimension, before the retained-expansion inspection prototype. Save
this source as `/tmp/dimension.x`:

```x2c
macro Expr $width() => 3;
macro Unit $make(Name $name) { int $name[$width()]; }
$make(values);
int main(void) { return sizeof(values); }
```

`builds/0/x2c translate --dump-code /tmp/dimension.x` emits
`int values[macro-invoke m-invoke];`. Ordinary translation with
`--out-dir /tmp/dimension-output` exits 1 with
`emit: failed to write interface file`. Parsed and transformed dumps both
retain the unresolved invocation. Passing `$width()` as an Expr argument to
`$make` instead produces `int values[3];` and translates successfully.

`src/parse/declarators.x` `_finish_fnmod` completes function parameters but
leaves dimension modifiers unchanged. Constructed declaration binding calls
that helper; transformation preserves the uninitialized declarator, and
`src/emit/declarations.x` `_array_declarator` tokenizes its dimension. This
is a separate compiler follow-up; inspection neither loses an executed
expansion in this probe nor causes the normal translation failure.

Adding `List cached = %("stack-check"); (void) cached;` at the start of
`static-local-flat-chain`'s `main` makes translation of its 4,000 additions
crash with a 256 KiB stack limit. The same augmented source fails before
and after the literal-slot ordering repair; the unchanged fixture passes.
This reduced-stack case remains separate from that repair and does not
establish a failure at the default stack limit.

Aggregate-contained local pointers, native callees that retain an address,
and exact-once resource finalization remain outside the current meta
ownership proof. Direct local-pointer tag parity does not establish those
larger shapes. Bare unknown native macro names retain native C initializer
rules; tags hidden inside an opaque native macro retain native scope. Pass
lowered local objects explicitly to native macros. The language reference
describes these native boundaries.

## Retired maintenance notes

- The compiler preserves discarded assignments,
  selected conditional arms, short-circuit branches and updates. The
  `meta-expression-effects` fixture prints matching explicit, folded and
  native results, including `discarded 3 3 3`.
- Destination conversion turns `Symbol empty = 0`
  to the declared tag before native methods. The same destination fixture
  checks composed String hash and pointer conversion. Direct local-address
  `Var.is_pointer`/`Var.is_reference` parity was verified in the post-merge
  review; aggregate and borrowed-pointer work remains open above.
- Static-initializer classification fixes baseline B01-B03. The
  `static-initializer-classification` fixture builds and prints
  `4 4 0 0 0 12 12`; it covers fixed-size `sizeof`, VLA-dependent local
  static initialization, and empty Array/Map statics.
- Meta numeric comparisons resolve builtin typedefs before choosing C
  arithmetic conversion. The former `Array.len()` versus integer mismatch
  is covered by `meta-collection-operations`. `meta-core-operations` also
  checks that lowered character literals retain the native character tag.

- Deferred static initialization fixes the three cases recorded against
  published `1de90da`: delayed `__COUNTER__` expansion, inline tags emitted
  inside the initializer helper, and local static aggregates containing
  nonconstant canonical String values. `static-native-source` checks source
  expansion order, macro redefinition, inline tag identity, and native
  stringizing/token-pasting together. Local static fixtures check once-only
  calls, const members and arrays, volatile reads, inferred bounds, stable
  addresses across retry, argument values, automatic state after Error,
  concurrent publication, thread-local storage, recursion, bounded-stack
  expression walks, and rejected goto/switch entry. The static-init unit suite
  additionally checks cross-thread cycles and waiter recovery, allocation
  retry, aligned storage across Context teardown, and thread cleanup.
- String classification already owned positive and negative `contains_digit`
  cases. It now includes empty and high-byte inputs; the String utility cases
  cover one-sided stripping, custom character sets, canonical unchanged and
  empty results, and successful and zero-length fill. `lfind`, `quote`, and
  `unquote` are obsolete names, not missing runtime operations; current search,
  representation, and parsing owners retain their existing coverage.
- Array, Map, and Match setup uses ordinary literals and dot notation where
  the old Var preambles added no coverage. Explicit construction remains in
  tests of construction and counted varargs. Interned-only Symbol parse tests
  no longer retain Scope; mutable-container and Match tests retain the scopes
  required by their allocation owners.
- Logger captures structured `LogEvent` records; Diagnostics captures List
  entries through a different emitter contract. A shared capture helper would
  obscure those contracts, so the proposed abstraction is retired.
- Map expansion's shared generator stages both arrays with `defer` before
  publishing them. Allocation failure during expansion is not forcibly
  injected. That coverage limitation does not justify adding a production
  allocator hook or another recurring test requirement solely for this note.
