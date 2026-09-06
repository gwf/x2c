# Status

## Recent Work
- Compiler phase fixtures cover focused token, AST, transform, emission,
  generated-file, diagnostic, and runtime behavior.
  Filtered symbol artifacts additionally own focused semantic Type values
  without copying the complete global table. `make verify-fixtures` checks
  expectations without rewriting them.
- AST declaration fixtures now distinguish declarator `fnmod` from semantic
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
- Exact fixtures now prove one-based token positions, token-width diagnostic
  carets, rejection of removed `$()` and `@()` literal forms, structured
  rejection of malformed braced forms, and transformed match/loop AST
  rendering. Empty native and boxed String representations are covered by the
  String and Var suites.
- Canonical scalar fixtures prove alternate legal specifier orders, promotion
  and mixed arithmetic, suffix-derived literal families, scalar typedef Var
  crossings, invalid combinations, and out-of-range integer-literal
  diagnostics.
- Native fixture programs now compile with the active build flags. The
  defer/try fixture proves optimized preservation of directly modified locals,
  parameters, cleanup guards, rethrow state, and finalizers.
- Type-initializer fixtures prove the exact hook signature, one owner per
  translation unit, guarded cache ordering, non-static entry ownership,
  static-helper trust, direct-call idempotence, and structured rejection of
  legacy `@init`.
- List and String canonicalization are covered directly: repeated and nested
  `cons` calls return identical cells, repeated `String.new` calls return the
  same interned String, and `String.intern_free` canonicalizes a separately
  allocated equal buffer. String completion additionally proves cached hash
  and length, transient/canonical freeing, bounded byte operations, empty
  search behavior, split/replace/partition utilities, and status-bearing
  numeric parsing.
- Empty Array and Map literals are covered as distinct allocated objects that
  can be mutated immediately. Boxing preserves their object identity, and the
  mutable-empty fixture proves that null pointers cannot be boxed under either
  mutable-container value tag.
- Runtime boundary regressions now cover empty Block pops, Array reduction,
  String bounds/search/null ordering, short file reads, unsigned-character
  conversion, invalid hexadecimal escapes, descending ranges, and Symbol
  encoding/scanner boundaries. Block and Buffer coverage now also proves
  checked growth, self-append, repeated fill, overlap handling, failure
  atomicity, text-only writes, embedded-NUL rejection, and multiline position
  state. The Map robustness tranche adds seven tests for growth, collision
  deletion, model churn, traversal, counted updates, and comparison laws.
  Runtime match completion adds typed-empty, fallback, normalized-guard,
  star-pattern, and status-API coverage. List compaction adds 16-byte-cell and
  50,000-cell iterative hot-path regressions. Scope coverage additionally
  proves allocation-list updates, direct named-slot allocation, statistics,
  zero-size behavior, stack growth, and terminal shutdown diagnostics. Counted
  Array construction preserves raw Null and rejects dynamic `void` literal
  elements at the Array owner. Packed-container Context coverage now proves
  all six typed Arrays and all three typed Maps through direct export and a
  nested Thread result, including pointer identity, aliases, canonical
  Strings, empty Strings, borrowed values, source close, later-bucket key
  collapse, recursive custom export, and subsequent growth.
- Var coverage now proves registered source/tag round trips, exact wide scalar
  boxing, content semantics for wide boxes, typed custom dispatch, and
  explicit construction failures. Equality and identity inspect `void`; fatal
  probes prove that direct hash, ordering, and iteration still reject it.
  VarOps coverage
  adds all 15 cross-tag numeric families, exact integer lanes, promotion,
  conversion failure, arithmetic, comparison, truthiness, and atomic compound
  updates. Iter and Map suites prove status-bearing control, raw Null Map
  traversal, and safe unsupported iteration. The `void` sentinel fixture proves
  List, Array, Map, and iterator value exclusion.
- Iter, Logger, File, and scanner completion now own their direct runtime
  contracts, hot-path benchmarks, and boundary fixtures. The root `bm-all`
  target runs every focused benchmark owner.
- Harness contract change (2026-07-16): `test-support.x` counts assertion
  failures and `TestHarness_run` fails a test iff assertions failed, it made
  no assertions, it threw, or it left extra pushed/retained scope state.
  Uncaught throws restore the active scope slot before formatting the payload.
  `TestFn` is now `void`; all suites swept to bare `EXPECT_*` statements -
  no more `int ok` threading or inverted return conventions. Added
  `EXPECT_LIST_EQ`, `TEST_FAIL`, and explicit skipped-test accounting.
  Inherited baseline held byte-identical through the sweep (148 passed, 875
  assertions), then 876 after the binder fix.
- Error migration correction (2026-07-27): the harness no longer catches a
  transfer. It fails on assertion failure, zero assertions, or unbalanced
  Scope state; ambient errors remain with their configured policy owner.
- Fixed `test-match-binder.x` polarity: it previously returned PASS when
  the `?ident`-binds-as-List bug manifested. The corrected test passes, so
  the underlying matcher bug is fixed; the test now guards against
  regression for real.
- Match statement binders now enter semantic arm scope as typed `Var` or
  `List` locals, definite assignment is enforced across guard operators, and
  the three corrected dynamic-operator runtime cases are active.
- The repository-stabilization fixtures prove brace-free Match parsing and
  valid per-binding volatile emission when a non-leading destructured local
  changes across `try`. Compiler-private AST tests reject operator nodes beyond
  the emitter-owned unary, binary, and ternary forms.
- Newest-feature runtime seams (2026-08-01): the Var suite cross-checks
  `Var.kind` against the ledger kind column for all 109 rows and covers
  `Var.clone_wide`; the typed-array suite covers every raise path, with
  `push` on a null array classified as the family
  `bad-arg` diagnostic; new `test-symbolset.x` and `test-protocols.x` suites
  own SymbolSet runtime behavior and the base-default/descriptor-dispatch
  seams behind protocol adoption. A fixture locks `@{...}` inside `%""` as
  literal segment text (the list-context rejection was already locked).

## Known Issues
- Numeric `$x` and `${expr}` String interpolation are executable tests;
  the former known-failure example is a checked showcase.

## Outstanding Items
- The String completion tranche closed the earlier broad gap; its remaining
  direct-name gaps are `contains_digit`, `lfind`, `lstrip`, `new_fill`,
  `quote`, `rstrip`, and `unquote`, plus lifecycle and dispatch adapters
  already exercised indirectly.
- Literal/dot-notation modernization sweep of `test-array.x`,
  `test-map.x`, `test-match-stmt.x` (verbose Var preambles -> `%[1, 2]`
  literals); drop unneeded `Scope.retain` from interned-only suites.
- Consider fixture helpers for the logger/diagnostics capture-sink
  duplication.

## Removed with the free-record pool (2026-08-07)

Map's storage moved to a parallel hash array and entry array, so the record
array, the record index, and the free-record pool no longer exist. Three tests
covered only that machinery and were removed rather than adapted:
`map_growth_reuses_all_pending_record_indexes`,
`map_expand_unwind_cleans_staged_storage`, and
`typed_map_expand_unwind_is_atomic`. The first tested pool harvesting and
reuse across growth. The other two forced a pool allocation failure to prove
expansion unwound without leaking; expansion now stages two arrays and relies
on `defer` for that, and there is no longer a hook to force the failure. Test
coverage fell by those three cases. Restoring unwind coverage needs an
injection point in `_core_expand`.
