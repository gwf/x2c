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

## Inspecting a feature's lowering

To see how a compiler stage transforms a feature, dump the AST before and after
that stage. Take a `foreach` loop:

```x2c
int sum(List numbers) {
  int total = 0;
  foreach(int n in numbers) total += n;
  return total;
}
```

Print the AST after lowering:

```sh
./builds/0/x2c translate --dump-transforms sum.x
```

```text
(block (declare (int) (bindings (bind (binding 4 "n") ())))
 (declare ("List")
  (bindings
   (op = (bind (binding 5 "_x2c_gensym_macro_object_0") ())
    (expr ("List") (ident (binding 2 "numbers"))))))
 (declare ("List")
  (bindings
   (op = (bind (binding 6 "_x2c_gensym_macro_cursor_0") ())
    (expr ("List") (ident (binding 5 "_x2c_gensym_macro_object_0"))))))
 (declare ("Var")
  (bindings (bind (binding 7 "_x2c_gensym_macro_cursor_output_0") ())))
 (at 20
  (while
   (expr (int)
    (call ... (ident (binding 8 "List_try_next")))
     (args (expr ("List") (ident (binding 5 "_x2c_gensym_macro_object_0")))
      (expr (opt-ref "List") (op & ...))
      (expr (opt-ref "Var") (op & ...)))))
   (block ...))))
```

The built-in source macro in `src/macros/macros.x`, `etc/compiler-prelude.x`, and
`src/builtins.x` has replaced `foreach` with declarations and a
`while` loop that calls `List_try_next`. The loop keeps the List, a cursor,
and the current element in generated locals; `List_try_next` advances the
cursor and stores the element through its reference arguments. The later
transform pass converts the yielded `Var` to `int` before `total += n`,
and it passes the cursor and element by address.
Compare `--dump-ast` with `--dump-transforms` to see those changes. The full
set of dump flags is listed under [compiler options](../reference/cli.md).

## Feature ownership

### Collection and String literals

- Parse: `src/literals/literals.x`
- Lower/generate: `src/components/collection-literals.x`, `src/transform/transform.x`,
  `src/cache.x`
- Runtime: `lib/list/list.x`, `lib/array/array.x`, `lib/map/map.x`, `lib/string/string.x`
- Tests: literal-cache and mutable-empty fixtures, collection suites
- See also: [collections](../guide/collections.md)

### String interpolation

- Parse: `src/literals/literals.x` for `$name` and `${expr}`, which are separate sites
- Type/convert: `Compiler.convert_segment_to_string` in `src/expressions/conversions.x`
  selects the conversion for each segment. A segment that is already a `Var`,
  canonical or aliased, renders through `Var_str` whatever its run-time tag; a
  numeric segment takes its nearest declared `T_str` converter when one exists
  and is
  boxed and rendered through `Var_str` otherwise
- Lower/generate: `src/transform/transform.x` converts each insertion, then
  `src/components/interpolation.x` joins them; see [builtin
  components](architecture.md#builtin-components)
- Runtime: `lib/string/string.x`, plus `Var.str` for the boxed segments
- Tests: interpolation suite
- See also: [values](../guide/values.md)

### Symbol and Atom literals

- Tokenize: `lib/tokenizer.x`, using the scanners in `lib/scan.x`
- Parse: `src/literals/literals.x`
- Lower/generate: `src/emit/emit.x`
- Runtime: `lib/symbol.x` for immediate `Symbol`s, `lib/atom.x` for spellings
  that do not fit a `Symbol`
- Tests: symbol suite and checked symbol example
- See also: [symbols and atoms](../guide/symbols.md)

### Indexing and slicing

- Parse/type: `src/expressions/expressions.x`, `src/type.x`
- Lower: `src/components/bracket-access.x` with ordinary ordered-call and
  conversion operations from `src/transform/transform.x`
- Runtime: collection helpers plus the shared bounds normalizer in
  `lib/common.x`
- Tests: index/slice suite and checked indexing example
- See also: [collections](../guide/collections.md)

### Method-style calls

- Parse/type: `src/expressions/expressions.x`, `src/type.x`
- Lower: `src/transform/transform.x`; a call that finds no member on a receiver with
  `delegate` fields goes through the one field path that provides it,
  which `src/components/delegate-members.x` finds
- Runtime: statically selected module function
- Tests: unit suites across runtime types and the delegate compiler fixtures

### Protocol adoptions

- Parse, publish, and resolve declarations and adoptions, and choose each
  member's owner: `src/protocol/protocol.x`; operator mappings:
  `src/operator-ledger.x`
- Write each conformance's adapters: `src/components/protocol-adapters.x`;
  see [builtin components](architecture.md#builtin-components)
- Runtime descriptors and their registration: `lib/dispatch.x`; built-in
  adoptions: `lib/protocols.x`
- Tests: protocol, adoption, and conformance compiler fixtures and the
  protocol-boundaries probe
- See also: [protocols](../guide/protocols.md)

### Compile-time macros and decorators

- Parse, import, hygiene, and expand: `src/macros/macros.x`
- Compiler operations for `meta` code, the `Code` and `Type` methods and
  the `x2c_` helpers: `lib/meta.x`
- Macro values, their application, and macro-valued `case` recognition:
  `lib/macrovalue/macrovalue.x`
- Compile-time Lisp boundary adapters: `etc/compiler-sdk.xlisp`
- `meta` arguments and results: `src/stage.x`; a unit's `meta` group and
  in-process staging: `src/meta-group/meta-group.x`; the project helper:
  `src/meta-project.x` builds it, `src/meta-helper-client.x` calls it, and
  `etc/meta-helper.x` answers, with the compiler queries that
  `tools/gen-meta-queries.sh` generates from `lib/meta.x` into
  `etc/meta-queries.x`
- Embedded native bindings: `etc/lisp-bindings.x`,
  `etc/lisp-bindings.xlisp`, `lib/lisp-targets/lisp-targets.x`, `lib/lisp/lisp.x`, and
  `lib/func/func.x`
- Tests: macro import, template, decorator, inline-Lisp, and inferred-binding
  compiler fixtures; Lisp and `Func` suites; compile-time-macros, decorators,
  and inline-lisp examples
- See also: [compile-time macros](../reference/language.md#compile-time-macros)

### Package imports and `with` names

- Parse: `src/parse/parse.x`
- Package name collection and resolution: `src/symtab/symtab.x`, `src/collect/collect.x`
- Manifest and native build ownership: `src/project/project.x`, `commands/build/build.x`, and
  `src/toolchain.x`
- Tests: import/package compiler fixtures and the import-greet example
- See also: [packages and
  imports](../reference/language.md#packages-and-import)

### Module blocks

- Splice the member files into the entry's text: `Compiler.module_source` in
  `src/collect/collect.x`, called for a unit's text in `src/frontend.x`, for every
  cold walk of an included file, and for the project `meta` scan in
  `src/meta-project.x`
- Member positions: the unit's `line_markers` rows, read by
  `Compiler.token_source`, `Compiler.token_column`, and
  `Compiler.text_source` in `src/diagnostics.x`; a replayed compile-time
  effect records its site in the member's own text through
  `Compiler.source_token`
- Member dependencies and the entry's content hash: `FileWalk` in
  `src/collect/collect.x`
- The `module` storage class: `_module_storage_form` in `src/parse/units.x`
  retypes the word as `static` under `Compiler.module_declaration`
- File-private statics: each marker row carries its file's prefix from
  `_file_prefix` in `src/collect/collect.x`; `_declared_key` in `src/symtab/symtab.x`
  respells a static's key with `Compiler.private_prefix` and
  `Compiler.declared_spelling`, which records prefixed spellings so derived
  names keep theirs; `Sym.get` and `_lookup_from` try the current
  file's key first, and `Compiler.unprefixed` restores the short name for
  Var tags and descriptors
- Tests: the `module-block` and `module-storage-class` compiler fixtures
- See also: [module blocks](../reference/language.md#module-blocks)

### Expression aliases

- Parse and expand: `src/macros/aliases.x` reads `alias` and `unalias` at file,
  module, block, aggregate, and enumerator positions and wraps braced bodies
- Scope entries: `Sym.define_alias` and `Sym.undefine_alias` in
  `src/symtab/bindings.x`
- Hooks: `src/statements.x` (block position), `src/parse/units.x` (file and
  module position), and `src/parse/types.x` (aggregate and enumerator bodies)
- Tests: the `alias-*` and `unalias-*` compiler fixtures
- See also: [expression
  aliases](../reference/language.md#expression-aliases-with-alias)

### The `with` statement

- Parse: `_with_statement` in `src/statements.x`
- Lower: `_with_expand` in `src/builtins.x`, reached through the
  `$x2c.with` decorator in `etc/compiler-prelude.x`
- Tests: the `with-*` compiler fixtures
- See also: [with](../reference/language.md#temporary-assignments-with-with)

### `auto` allocation regions

- Recognize: `Compiler.auto_region_form` in `src/parse/auto.x`, asked by
  invocation recognition in `src/macros/invocations/recognition.x` and the
  script-statement queries in `src/parse/units.x`
- Lower: `_scope_expand` in `src/builtins.x`, reached through the
  `$x2c.auto.region` and `$x2c.auto.destination` decorators in
  `etc/compiler-prelude.x`
- Tests: the `scope-*` and `auto-*` compiler fixtures
- See also: [allocation regions](../reference/language.md#allocation-regions)

### Exact Var-tag tests with `is` and `is not`

- Parse, type, and lower: `src/expressions/expressions.x` types each test as a
  `Var.is`, `Var.is_void`, or constant-row `Var.is_row` call; `src/type.x`
  supplies the tag facts
- Runtime tag representation: `lib/var/var.x`, `lib/common.x`
- Tests: is-type and is-not compiler fixtures plus `Var` suites
- See also: [exact Var-tag
  tests](../reference/language.md#exact-var-tag-tests-with-is-and-is-not)

### List destructuring

- Parse declarations and binders: `src/parse/parse.x`, `src/statements.x`
- Type access: `src/type.x`; lower: `src/components/destructuring.x`,
  dispatched from `src/transform/transform.x`
- Runtime source values: `lib/list/list.x`
- Tests: destructuring suite and list-destructuring compiler fixtures

### Inline Lisp bindings

- Parse and expand `$lisp.bind`, `$lisp.binding`, and `$lisp.install`:
  `src/macros/macros.x`, `etc/lisp-bindings.x`, and
  `etc/lisp-bindings.xlisp`
- Runtime call boundary: `lib/lisp/lisp.x`, `lib/func/func.x`
- Tests: Lisp binding compiler fixtures, Lisp/`Func` suites, and the
inline-lisp example
- See also: [compile-time macros](../reference/language.md#compile-time-macros)

### Var boxing, conversion, operations, and dispatch

- Type selection: `src/type.x`
- Typedef identity and scopes: `src/symtab/symtab.x`, `src/statements.x`
- Conversion lowering: `src/expressions/expressions.x`
- Protocol operator selection: `src/expressions/expressions.x`
- Dynamic operators: `src/components/dynamic-operators.x`
- Truthiness and native emission: `src/transform/transform.x`, `src/emit/emit.x`
- Sentinel literal parsing and C spelling: `src/literals/literals.x`, `src/emit/emit.x`;
  expression context distinguishes the literal from C `void` type positions
- Runtime representation: `lib/common.x`, `lib/var/var.x`, `lib/scope/scope.x`
- Numeric metadata, conversion, and failure causes: `lib/var/conversion.x`;
  shared representation declarations: `lib/common.x`
- Arithmetic, truthiness, and compound assignment: `lib/var/operators.x`
- Comparison policy and nonnumeric dispatch: `lib/dispatch.x`; exact numeric
  comparison mechanics delegate to `Var.integer_compare` and
  `Var.integer_floating_compare`
- Typedefs: declarations are file-scope; direct and chained aliases of `Var`
  use the same conversions and operators as `Var`
- Numeric conversion: all 15 numeric tags use one implementation that raises
  the appropriate `Error` cause on failure; `long`/`ulong`, `llong`/`ullong`,
  and `ldouble` name native `long`, `long long`, and `long double` families
  rather than fixed widths
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

- Parse: `src/parse/parse.x`, `src/literals/literals.x`, `src/expressions/expressions.x`
- Canonical type owner: `src/type.x`
- Conversion: `src/transform/transform.x`, `src/expressions/expressions.x`
- Runtime representation: `lib/var/var.x`, `lib/scope/scope.x`
- Tests: canonical scalar fixture, invalid-scalar and overflow diagnostics,
  `Var` suite
- See also: [values and Var](../guide/values.md)

### Lambdas

- Parse and resolve captures: `src/literals/literals.x`, `src/lambdas.x`
- Lower: `src/components/lambda-functions.x`, dispatched from
  `src/transform/transform.x`
- Direct `Func` calls and conversions: `src/callables/callables.x`,
  `src/expressions/expressions.x`
- Runtime: `lib/func/func.x` and receiving callback APIs
- Tests: captured-lambda and lambda-lowering fixtures, lambda and `Func` suites

### Foreach

- Parse and expand: built-in source macro support in `src/macros/macros.x` and
  `etc/compiler-prelude.x`; the expansion algorithm in
  `src/builtins.x`
- Lower/generate the expanded loop: `src/transform/transform.x`, `src/emit/emit.x`
- Runtime: `lib/iter.x` and collection adapters; `Iter.try_next` returns the
  traversal status
- Tests: `foreach` fixture, `Iter` suite, and checked example
- See also: [iteration](../guide/iteration.md)

### Status-bearing Map operations

- Runtime owner: `lib/map/map.x`
- Literal boundary: `src/components/collection-literals.x`; see [builtin
  components](architecture.md#builtin-components)
- Generic routing: `lib/dispatch.x`
- Value-returning wrappers: `Map.get` and `Map.del`
- Cursor contract: structural mutation invalidates outstanding traversal state
- Tests: `Map` and `Iter` suites plus the `void`-sentinel and raw `Null`
  coverage
- See also: [collections](../guide/collections.md)

### Counted Array construction

- Runtime owner: `lib/array/array.x` through `Array.update_n` and `Array.push`
- Literal boundary: `src/components/collection-literals.x`; see [builtin
  components](architecture.md#builtin-components)
- Value contract: raw `Null` is data; `void` is rejected
- Tests: `Array` suite and the counted-literal compiler fixture
- See also: [collections](../guide/collections.md)

### Var values in printf-family formats

- Parse and type the call: `src/expressions/expressions.x`
- Lower: `src/components/printf-format.x`; see [builtin
  components](architecture.md#builtin-components)
- Runtime: `Var.convert` in `lib/var/conversion.x` and `Var.str` in
  `lib/dispatch.x`
- Tests: the `printf-var` compiler fixtures
- See also: [values and Var](../guide/values.md)

### Match statement

- Parse: `src/statements.x`
- Lower: `src/components/pattern-match.x`; see [builtin
  components](architecture.md#builtin-components)
- Native emission: `src/emit/emit.x`
- Runtime: `lib/match/match.x` and the plan modules listed in [the runtime
  boundary](architecture.md#the-runtime-boundary); patterns and binding sets
  are ordinary `List`s from `lib/list/list.x`
- Tests: match suites and checked nested example
- See also: [pattern matching](../guide/match.md)

### String switch

- Parse: `src/statements.x`
- Lower: `src/components/string-switch.x`; see [builtin
  components](architecture.md#builtin-components)
- Tests: the `string-switch` and `rewrite-string-switch` compiler fixtures
- See also: [C control flow](../reference/language.md#c-control-flow)

### Raise, filtered catch, finally, and defer

- Parse: `src/statements.x`
- Lower/generate: `src/transform/transform.x`, `src/components/raise.x`,
  `src/components/try-catch.x` (see [builtin
  components](architecture.md#builtin-components)), `src/cleanup/cleanup.x`,
  `src/emit/emit.x`
- Runtime: `lib/exception.x` implements the frames and jumps for transfer
  and cleanup; `lib/error/error.x` owns handlers, policy, watermarks, accumulated
  records, matching, and transferring registration lifetime
- Tests: optimized `defer`/try and filtered-catch compiler fixtures,
  exception/`defer`/`Error` suites, and fatal/floor subprocess probes
- See also: [errors and cleanup](../guide/exceptions.md), and
  [scopes and lifetime](../guide/memory.md) for what cleanup releases

### Type-owned initialization

- Parse: `src/parse/parse.x`
- Lower/generate: `src/generate/generate.x`, `src/cache.x`
- Runtime: generated guard plus `TYPE.initialize()`
- Boundary: [generation and cache
  staging](architecture.md#generation-and-cache-staging) lists the functions
  that check each guard
- Tests: type-initializer fixtures

### Structured diagnostics

- Produce: all parser phases
- Collect/render: `src/diagnostics.x`
- Destination: standard error, written directly; `src/report.x` suspends the
  progress line first. `--diagnostics-file` also writes JSON Lines diagnostics
- Tests: parse-error, diagnostic-width, and invalid-list-splice fixtures plus
  the diagnostics suite

The exact location fields, one-based coordinates, token-width rendering,
CLI default of 20 errors, low-level one-error default, and reusable store
limit are documented in `agents/logger-and-diagnostics-guide.md`.

## Compiler phase boundaries

[The compiler pipeline](architecture.md#the-compiler-pipeline) gives the
phase order and the modules in each phase, and
[module ownership](architecture.md#module-ownership) lists each module's
responsibility.

## Shared Lisp initialization

The compiler and `Lisp.new()` load the same `etc/init.xlisp`: the evaluator
primitives, macros, native bindings, and the standard algorithms (list
traversal, numeric wrappers, selectors, predicates, and pattern helpers).
The algorithms without callbacks are x2c functions in `lib/lisp-targets/algorithms.x`,
which that file binds by name; `map`, `filter`, and `foldl` stay in Lisp.
Those algorithms use fixed primitive operations internally; their public
Lisp names remain replaceable. In particular, rebinding `car`, `cdr`, or
`cons` does not change `filter`.

The compiler's built-in macro algorithms are compiler functions in
`src/builtins.x`, bound into the shared compile-time session under the
names the built-in macros call. They are bound at the compiler-only
boundary; they are not part of `Lisp.new()`. Scope expansion, foreach lowering, and deferred class defaults
reuse the ordinary compiler queries and syntax builders.

Native Lisp signature and binding algorithms are compiler functions in
`src/builtins.x` under `_x2c.binding_*`, and `etc/lisp-bindings.xlisp`
defines the Lisp entry points over them. Importing that file loads only
functions. The compiler initializes binding rows and
sealed groups when it installs the binding macros for each translation unit,
so signature preloading cannot put mutable group state in the shared parent.
