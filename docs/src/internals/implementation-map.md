# Implementation Map

x2c translates its extensions into C expressions, statements, and runtime
calls. This chapter identifies the parser, transforms, runtime modules, and
tests for each feature.

To follow a feature from syntax to generated C, start with its entry below and
read the files in the listed order.

What the features *mean* is documented elsewhere:

- [language reference](../reference/language.md): syntax and behavior
- [idioms](../guide/idioms.md): how to use each feature well
- [standard library overview](../library/overview.md): runtime contracts
- [architecture](architecture.md): the pipeline as a whole

The [compiler API reference](compiler-api/index.md) and
[runtime module reference](../library/modules/index.md) describe individual
functions and types.

## Watching a feature get lowered

To see how a compiler stage transforms a feature, dump the AST before and after
that stage. Take a `foreach` loop:

```x2c
int sum(List numbers) {
  int total = 0;
  foreach(Var n, numbers) total += n;
  return total;
}
```

Ask for the AST after parsing and macro expansion:

```sh
./builds/0/x2c translate --dump-transforms sum.x
```

```text
(block
 (declare ("Var") (bindings (bind (binding 4 "n") ())))
 (declare ("Iter")
  (bindings (op = (bind (binding 5 "_x2c_macro_iterator_0") ())
   (expr ("Iter") (call ... (ident (binding 10 "List_iter"))
    (args ... (expr (* struct "Iter") (op & ...))))))))
 (while
  (expr (int) (call ... (ident (binding 11 "Iter_try_next")) ...))
  (block ...)))
```

The built-in source macro in `src/macros.x`, `etc/builtin-macros.xmacro`, and
`etc/builtin-macros.xlisp` has replaced `foreach` with declarations and a
`while` loop that call `List_iter` and `Iter_try_next`. The final `List_iter`
argument is a zero-initialized compound literal whose block lifetime holds the
iterator state. The later transform pass replaces `total += n` with the
run-time compound assignment helper for that scalar tag. Compare `--dump-ast`
with `--dump-transforms` to see that second change. The full set of dump flags
is listed under [compiler options](../reference/cli.md).

## Feature ownership

### Collection and String literals

- Parse: `src/literals.x`
- Lower/generate: `src/transform.x`, `src/cache.x`
- Runtime: `lib/list.x`, `lib/array.x`, `lib/map.x`, `lib/string.x`
- Tests: literal-cache and mutable-empty fixtures, collection suites
- See also: [collections](../guide/collections.md)

### String interpolation

- Parse: `src/literals.x` for `$name` and `${expr}`, which are separate sites
- Type/convert: `Compiler.convert_segment_to_string` in `src/expressions.x`
  selects the conversion for each segment. A segment that is already a `Var`,
  canonical or aliased, renders through `Var_str` whatever its run-time tag; a
  numeric segment takes its nearest declared `T_str` converter when one exists
  and is
  boxed and rendered through `Var_str` otherwise
- Lower/generate: `src/transform.x` joins the segments with `String_join`
- Runtime: `lib/string.x`, plus `Var.str` for the boxed segments
- Tests: interpolation suite
- See also: [values](../guide/values.md)

### Symbol and Atom literals

- Tokenize: `lib/tokenizer.x`, using the scanners in `lib/scan.x`
- Parse: `src/literals.x`
- Lower/generate: `src/emit.x`
- Runtime: `lib/symbol.x` for immediate `Symbol`s, `lib/atom.x` for spellings
  that do not fit a `Symbol`
- Tests: symbol suite and checked symbol example
- See also: [symbols and atoms](../guide/symbols.md)

### Indexing and slicing

- Parse/type: `src/expressions.x`, `src/type.x`
- Lower: `src/transform.x`
- Runtime: collection helpers plus the shared bounds normalizer in
  `lib/common.x`
- Tests: index/slice suite and checked indexing example
- See also: [collections](../guide/collections.md)

### Method-style calls

- Parse/type: `src/expressions.x`, `src/type.x`
- Lower: `src/transform.x`
- Runtime: statically selected module function
- Tests: unit suites across runtime types

### Compile-time macros and decorators

- Parse, import, hygiene, and expand: `src/macros.x`
- Compile-time Lisp operations: `etc/compiler-sdk.xlisp`
- Embedded native bindings: `etc/lisp-bindings.xmacro`,
  `etc/lisp-bindings.xlisp`, `lib/lisp.x`, and `lib/func.x`
- Tests: macro import, template, decorator, inline-Lisp, and inferred-binding
  compiler fixtures; Lisp and `Func` suites; compile-time-macros, decorators,
  and inline-lisp examples
- See also: [compile-time macros](../reference/language.md#compile-time-macros)

### Package imports and `with` names

- Parse: `src/parse.x`
- Package name collection and resolution: `src/compiler.x`, `src/collect.x`
- Manifest and native build ownership: `src/project.x`, `src/build.x`, and
  `src/toolchain.x`
- Tests: import/package compiler fixtures and the import-greet example
- See also: [packages and
  imports](../reference/language.md#packages-and-import)

### Exact Var-tag tests with `is` and `is not`

- Parse and type selection: `src/expressions.x`, `src/type.x`
- Lower and emit: `src/transform.x`, `src/emit.x`
- Runtime tag representation: `lib/var.x`, `lib/common.x`
- Tests: is-type and is-not compiler fixtures plus `Var` suites
- See also: [exact Var-tag
  tests](../reference/language.md#exact-var-tag-tests-with-is-and-is-not)

### List destructuring

- Parse declarations and binders: `src/parse.x`, `src/statements.x`
- Type and lower access: `src/type.x`, `src/transform.x`
- Runtime source values: `lib/list.x`
- Tests: destructuring suite and list-destructuring compiler fixtures

### Inline Lisp bindings

- Parse and expand `$lisp.bind`, `$lisp.binding`, and `$lisp.install`:
  `src/macros.x`, `etc/lisp-bindings.xmacro`, and
  `etc/lisp-bindings.xlisp`
- Runtime call boundary: `lib/lisp.x`, `lib/func.x`
- Tests: Lisp binding compiler fixtures, Lisp/`Func` suites, and the
inline-lisp example
- See also: [compile-time macros](../reference/language.md#compile-time-macros)

### Var boxing, conversion, operations, and dispatch

- Type selection: `src/type.x`
- Typedef identity and scopes: `src/compiler.x`, `src/statements.x`
- Conversion lowering: `src/expressions.x`
- Operator and truthiness lowering: `src/transform.x`, `src/emit.x`
- Sentinel literal parsing and C spelling: `src/literals.x`, `src/emit.x`;
  expression context distinguishes the literal from C `void` type positions
- Runtime representation: `lib/common.x`, `lib/var.x`, `lib/scope.x`
- Numeric metadata, conversion, and failure causes: `lib/varconvert.x`;
  shared representation declarations: `lib/common.x`
- Arithmetic, truthiness, and compound assignment: `lib/varops.x`
- Comparison policy and nonnumeric dispatch: `lib/dispatch.x`; exact numeric
  comparison mechanics delegate to `Var.integer_compare` and
  `Var.integer_floating_compare`
- Typedefs: declarations are file-scope; direct and chained aliases of `Var`
  use the same conversions and operators as `Var`
- Numeric conversion: all 15 numeric tags use one implementation that raises
  the appropriate `Error` cause on failure; `long`/`ulong`, `llong`/`ullong`, and
  `ldouble` name native `long`, `long long`, and `long double` families rather
  than fixed widths
- Limits: numeric-to-`String` conversion remains partial; other nonnumeric
  values use their declared conversions; helper-backed collection, enum, and
  bit-field compound assignment are unsupported; the C compiler checks ordinary
  C lvalue legality
- Sentinel contract: equality, identity, exact `is void`, and rendering inspect
  `void`; hashing, ordering, truthiness, iteration, conversion, arithmetic, and
  updates retain `<void-op>` behavior
- Tests: `Var`/`File`/VarOps suites and wide/custom, var-alias-crossings,
  var-numeric-lowering, var-numeric-conversions,
  var-native-lvalue-boundaries, var-truthy-`void`, var-nonnumeric-operator,
  var-unary-operator, var-helper-compound, var-enum-compound,
  var-bitfield-compound, and local-typedef compiler fixtures
- See also: [values and Var](../guide/values.md)

### Scalar declarations, literals, and arithmetic

- Parse: `src/parse.x`, `src/literals.x`, `src/expressions.x`
- Canonical type owner: `src/type.x`
- Conversion: `src/transform.x`, `src/expressions.x`
- Runtime representation: `lib/var.x`, `lib/scope.x`
- Tests: canonical scalar fixture, invalid-scalar and overflow diagnostics,
  `Var` suite
- See also: [values and Var](../guide/values.md)

### Lambdas

- Parse: `src/literals.x`
- Lower and direct `Func` calls: `src/lambda.x`, `src/transform.x`,
  `src/expressions.x`
- Runtime: `lib/func.x` and receiving callback APIs
- Tests: captured-lambda and lambda-lowering fixtures, lambda and `Func` suites

### Foreach

- Parse and expand: built-in source macro support in `src/macros.x` and
  `etc/builtin-macros.xmacro`; private lowering in
  `etc/builtin-macros.xlisp`
- Lower/generate the expanded loop: `src/transform.x`, `src/emit.x`
- Runtime: `lib/iter.x` and collection adapters; `Iter.try_next` owns status
- Tests: `foreach` fixture, `Iter` suite, and checked example
- See also: [iteration](../guide/iteration.md)

### Status-bearing Map operations

- Runtime owner: `lib/map.x`
- Literal boundary: `src/emit.x` emits counted `Map.update_n` construction
- Generic routing: `lib/dispatch.x`
- Value-returning wrappers: `Map.get` and `Map.del`
- Cursor contract: structural mutation invalidates outstanding traversal state
- Tests: `Map` and `Iter` suites plus the `void`-sentinel and raw `Null`
  coverage
- See also: [collections](../guide/collections.md)

### Counted Array construction

- Runtime owner: `lib/array.x` through `Array.update_n` and `Array.push`
- Literal boundary: `src/emit.x` emits counted `Array.update_n` construction
- Value contract: raw `Null` is data; `void` is rejected
- Tests: `Array` suite and the counted-literal compiler fixture
- See also: [collections](../guide/collections.md)

### Match statement

- Parse: `src/statements.x`
- Lower/generate: `src/transform.x`, `src/emit.x`; emitted code calls
  `List.match`
- Runtime: `lib/match.x` owns pattern semantics and plan compilation;
  `lib/match-machine.x` executes plans over wordcode and state definitions
  from `lib/machine.x`; patterns and binding sets are ordinary `List`s from
  `lib/list.x`
- Tests: match suites and checked nested example
- See also: [pattern matching](../guide/match.md)

### Raise, filtered catch, finally, and defer

- Parse: `src/statements.x`
- Lower/generate: `src/transform.x`, `src/emit.x`
- Runtime: `lib/exception.x` owns the frame/jump engine for transfer and
  cleanup; `lib/error.x` owns handlers, policy, watermarks, accumulated
  records, matching, and transferring registration lifetime
- Tests: optimized `defer`/try and filtered-catch compiler fixtures,
  exception/`defer`/`Error` suites, and fatal/floor subprocess probes
- See also: [errors and cleanup](../guide/exceptions.md), and
  [scopes and lifetime](../guide/memory.md) for what cleanup releases

### Type-owned initialization

- Parse: `src/parse.x`
- Lower/generate: `src/generate.x`, `src/cache.x`
- Runtime: generated guard plus `TYPE.initialize()`
- Boundary: non-static functions enter the guard; static helpers trust their
  guarded caller or the already-guarded initializer body
- Tests: type-initializer fixtures

### Structured diagnostics

- Produce: all parser phases
- Collect/render: `src/diagnostics.x`
- Destination: standard error, written directly; `src/report.x` suspends the
  progress line first. Nothing is logged to a file
- Tests: parse-error, diagnostic-width, and invalid-list-splice fixtures plus
  the diagnostics suite

The exact location fields, one-based coordinates, token-width rendering,
one-error compiler default, and reusable store limit are documented in
`agents/logger-and-diagnostics-guide.md`.

## Compiler phase boundaries

The main translation steps are:

1. `lib/tokenizer.x` turns scanner results into tokens.
2. `src/parse.x` coordinates declarations and top-level source.
3. `src/expressions.x`, `src/statements.x`, and `src/literals.x` construct
   typed AST forms; `src/ast.x` owns the shared node contracts they build to.
4. `src/type.x` supplies type facts and canonical forms.
5. `src/transform.x` lowers most extensions; `src/lambda.x` owns lambda
   helper and adapter synthesis.
6. `src/generate.x` partitions the translation unit and installs init
   scaffolding; `src/cache.x` owns literal-cache initialization.
7. `src/emit.x` emits C tokens and `src/format.x` formats them.

Global type information reaches the parser outside that
pipeline. `src/collect.x` gathers global symbol types by shallow-parsing raw
source and splicing quote-includes in preprocessor order, and
`src/snapshot.x` reads and writes the deterministic symbol snapshot that
covers the runtime under `lib/`.

`src/compiler.x` owns compiler state and symbol scopes. `src/diagnostics.x`
owns structured errors. `src/utils.x` owns host-environment and process
helpers, including the C preprocessor process boundary. `src/main.x` owns
process initialization, the translation loop, and phase dispatch;
`src/cli.x` owns the option table, command selection, and help rendering.

Each feature entry lists the relevant parser, transforms, runtime code, and
tests so you can follow its complete implementation.
