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
(block (declare ("Var") (bindings (bind (binding 4 "n") ())))
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

The built-in source macro in `src/macros.x`, `etc/builtin-macros.x`, and
`src/builtins.x` has replaced `foreach` with declarations and a
`while` loop that calls `List_try_next`. The loop keeps the List, a cursor,
and the current element in generated locals; `List_try_next` advances the
cursor and stores the element through its reference arguments. The later
transform pass replaces `total += n` with the run-time compound assignment
helper for that scalar tag, and it passes the cursor and element by address.
Compare `--dump-ast` with `--dump-transforms` to see those changes. The full
set of dump flags is listed under [compiler options](../reference/cli.md).

## Feature ownership

### Collection and String literals

- Parse: `src/literals.x`
- Lower/generate: `src/component-literals.x`, `src/transform.x`, `src/cache.x`
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
- Lower/generate: `src/component-interpolation.x` joins the segments with
  `String_join`, a literal rewrite on the `segments` head; `src/transform.x`
  converts each insertion and moves ordered parts ahead of the join
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
- Lower: `src/component-access.x` with ordinary ordered-call and conversion
  operations from `src/transform.x`
- Runtime: collection helpers plus the shared bounds normalizer in
  `lib/common.x`
- Tests: index/slice suite and checked indexing example
- See also: [collections](../guide/collections.md)

### Method-style calls

- Parse/type: `src/expressions.x`, `src/type.x`
- Lower: `src/transform.x`; a call that finds no member on a receiver with
  `delegate` fields goes through the one field path that provides it,
  which `src/component-delegate.x` finds
- Runtime: statically selected module function
- Tests: unit suites across runtime types and the delegate compiler fixtures

### Protocol adoptions

- Parse, publish, and resolve declarations and adoptions, and choose each
  member's owner: `src/protocol.x`; operator mappings:
  `src/operator-ledger.x`
- Write forwarding members, `Var` descriptor thunks, method tables, and
  descriptor registration: `src/component-protocols.x`, on the `conform`
  form `src/protocol.x` presents for each conformance
- Runtime descriptors and their registration: `lib/dispatch.x`; built-in
  adoptions: `lib/protocols.x`
- Tests: protocol, adoption, and conformance compiler fixtures and the
  protocol-boundaries probe
- See also: [protocols](../guide/protocols.md)

### Compile-time macros and decorators

- Parse, import, hygiene, and expand: `src/macros.x`
- Compiler operations for `meta` code, the `Code` and `Type` methods and
  the `x2c_` helpers: `lib/meta.x`
- Macro values, their application, and macro-valued `case` recognition:
  `lib/macro-value.x`
- Compile-time Lisp boundary adapters: `etc/compiler-sdk.xlisp`
- `meta` arguments and results: `src/stage.x`; a unit's `meta` group and
  in-process staging: `src/meta-group.x`; the project helper:
  `src/meta-project.x` builds it, `src/meta-helper-client.x` calls it, and
  `etc/meta-helper.x` answers, with the compiler queries that
  `tools/gen-meta-queries.sh` generates from `lib/meta.x` into
  `etc/meta-queries.x`
- Embedded native bindings: `etc/lisp-bindings.x`,
  `etc/lisp-bindings.xlisp`, `lib/lisp-targets.x`, `lib/lisp.x`, and
  `lib/func.x`
- Tests: macro import, template, decorator, inline-Lisp, and inferred-binding
  compiler fixtures; Lisp and `Func` suites; compile-time-macros, decorators,
  and inline-lisp examples
- See also: [compile-time macros](../reference/language.md#compile-time-macros)

### Package imports and `with` names

- Parse: `src/parse.x`
- Package name collection and resolution: `src/symbols.x`, `src/collect.x`
- Manifest and native build ownership: `src/project.x`, `commands/build/build.x`, and
  `src/toolchain.x`
- Tests: import/package compiler fixtures and the import-greet example
- See also: [packages and
  imports](../reference/language.md#packages-and-import)

### Module blocks

- Splice the member files into the entry's text: `Compiler.module_source` in
  `src/collect.x`, called for a unit's text in `src/frontend.x`, for every
  cold walk of an included file, and for the project `meta` scan in
  `src/meta-project.x`
- Member positions: the unit's `line_markers` rows, read by
  `Compiler.token_source`, `Compiler.token_column`, and
  `Compiler.text_source` in `src/diagnostics.x`; a replayed compile-time
  effect records its site in the member's own text through
  `Compiler.source_token`
- Member dependencies and the entry's content hash: `FileWalk` in
  `src/collect.x`
- The `module` storage class: `_module_storage_form` in `src/parse.x`
  retypes the word as `static` under `Compiler.module_declaration`
- File-private statics: each marker row carries its file's prefix from
  `_file_prefix` in `src/collect.x`; `_declared_key` in `src/symbols.x`
  respells a static's key with `Compiler.private_prefix` and
  `Compiler.declared_spelling`, which records prefixed spellings so derived
  names keep theirs; `Sym.get` and `_lookup_from` try the current
  file's key first, and `Compiler.unprefixed` restores the short name for
  Var tags and descriptors
- Tests: the `module-block` and `module-storage-class` compiler fixtures
- See also: [module blocks](../reference/language.md#module-blocks)

### Exact Var-tag tests with `is` and `is not`

- Parse, type, and lower: `src/expressions.x` types each test as a
  `Var.is`, `Var.is_void`, or constant-row `Var.is_row` call; `src/type.x`
  supplies the tag facts
- Runtime tag representation: `lib/var.x`, `lib/common.x`
- Tests: is-type and is-not compiler fixtures plus `Var` suites
- See also: [exact Var-tag
  tests](../reference/language.md#exact-var-tag-tests-with-is-and-is-not)

### List destructuring

- Parse declarations and binders: `src/parse.x`, `src/statements.x`
- Type access: `src/type.x`; lower: `src/component-destructuring.x`,
  dispatched from `src/transform.x`
- Runtime source values: `lib/list.x`
- Tests: destructuring suite and list-destructuring compiler fixtures

### Inline Lisp bindings

- Parse and expand `$lisp.bind`, `$lisp.binding`, and `$lisp.install`:
  `src/macros.x`, `etc/lisp-bindings.x`, and
  `etc/lisp-bindings.xlisp`
- Runtime call boundary: `lib/lisp.x`, `lib/func.x`
- Tests: Lisp binding compiler fixtures, Lisp/`Func` suites, and the
inline-lisp example
- See also: [compile-time macros](../reference/language.md#compile-time-macros)

### Var boxing, conversion, operations, and dispatch

- Type selection: `src/type.x`
- Typedef identity and scopes: `src/symbols.x`, `src/statements.x`
- Conversion lowering: `src/expressions.x`
- Protocol operator selection: `src/expressions.x`
- Dynamic operators: `src/component-operators.x`
- Truthiness and native emission: `src/transform.x`, `src/emit.x`
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

- Parse and resolve captures: `src/literals.x`, `src/lambdas.x`
- Lower: `src/component-lambdas.x`, dispatched from `src/transform.x`
- Direct `Func` calls and conversions: `src/callables.x`,
  `src/expressions.x`
- Runtime: `lib/func.x` and receiving callback APIs
- Tests: captured-lambda and lambda-lowering fixtures, lambda and `Func` suites

### Foreach

- Parse and expand: built-in source macro support in `src/macros.x` and
  `etc/builtin-macros.x`; the expansion algorithm in
  `src/builtins.x`
- Lower/generate the expanded loop: `src/transform.x`, `src/emit.x`
- Runtime: `lib/iter.x` and collection adapters; `Iter.try_next` owns status
- Tests: `foreach` fixture, `Iter` suite, and checked example
- See also: [iteration](../guide/iteration.md)

### Status-bearing Map operations

- Runtime owner: `lib/map.x`
- Literal boundary: `src/component-literals.x` builds counted
  `Map.update_n` construction
- Generic routing: `lib/dispatch.x`
- Value-returning wrappers: `Map.get` and `Map.del`
- Cursor contract: structural mutation invalidates outstanding traversal state
- Tests: `Map` and `Iter` suites plus the `void`-sentinel and raw `Null`
  coverage
- See also: [collections](../guide/collections.md)

### Counted Array construction

- Runtime owner: `lib/array.x` through `Array.update_n` and `Array.push`
- Literal boundary: `src/component-literals.x` builds counted
  `Array.update_n` construction
- Value contract: raw `Null` is data; `void` is rejected
- Tests: `Array` suite and the counted-literal compiler fixture
- See also: [collections](../guide/collections.md)

### Var values in printf-family formats

- Parse and type the call: `src/expressions.x`
- Lower: `src/component-printf.x` reads the static format once and converts
  each `Var` value a conversion consumes, one call pattern per family member
- Runtime: `Var.convert` in `lib/varconvert.x` and `Var.str` in
  `lib/dispatch.x`
- Tests: the `printf-var` compiler fixtures
- See also: [values and Var](../guide/values.md)

### Match statement

- Parse: `src/statements.x`
- Lower: `src/component-match.x` emits direct tests for static patterns and
  capture storage for runtime matching
- Native emission: `src/emit.x`
- Runtime: `lib/match.x` owns pattern semantics; `lib/match-plan.x`
  compiles patterns to plans, `lib/match-cache.x` retains them, and
  `lib/match-machine.x` executes them over wordcode and state definitions
  from `lib/machine.x`; patterns and binding sets are ordinary `List`s from
  `lib/list.x`
- Tests: match suites and checked nested example
- See also: [pattern matching](../guide/match.md)

### String switch

- Parse: `src/statements.x`
- Lower: `src/component-string-switch.x` numbers the labels a switch on a
  `String` owns and switches on a shared helper's result
- Tests: the `string-switch` and `rewrite-string-switch` compiler fixtures
- See also: [C control flow](../reference/language.md#c-control-flow)

### Raise, filtered catch, finally, and defer

- Parse: `src/statements.x`
- Lower/generate: `src/transform.x`; `src/component-raise.x` converts a
  `raise`'s code and details; `src/component-try.x` lowers `try` to a
  landing form; `src/cleanup.x` places cleanup on every exit from a region;
  `src/emit.x`
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
  progress line first. `--diagnostics-file` also writes JSON Lines diagnostics
- Tests: parse-error, diagnostic-width, and invalid-list-splice fixtures plus
  the diagnostics suite

The exact location fields, one-based coordinates, token-width rendering,
CLI default of 20 errors, low-level one-error default, and reusable store
limit are documented in `agents/logger-and-diagnostics-guide.md`.

## Compiler phase boundaries

The main translation steps are:

1. `lib/tokenizer.x` turns scanner results into tokens.
2. `src/parse.x` coordinates declarations and top-level source.
3. `src/expressions.x`, `src/statements.x`, and `src/literals.x` construct
   typed AST forms; `src/ast.x` owns the shared node contracts they build to.
4. `src/type.x` supplies type facts and canonical forms.
5. `src/transform.x` normalizes the typed forms and dispatches each
   feature a shipped component owns to its rules, such as lambdas to
   `src/component-lambdas.x`; `src/callables.x` owns `Func` adapter
   synthesis.
6. `src/cleanup.x` names each `defer` region's runtime record and each
   landing's frame, and places cleanup statements on every exit that leaves
   a region; `src/component-try.x` answers the landing form of a `try`.
7. `src/generate.x` partitions the translation unit and installs init
   scaffolding; `src/cache.x` owns literal-cache initialization.
8. `src/emit.x` emits C tokens and `src/format.x` formats them.

Global type information reaches the parser outside that
pipeline. `src/collect.x` gathers global symbol types by shallow-parsing raw
source and splicing quote-includes in preprocessor order, replays the
runtime prelude from the runtime `x2c.xi` interface, and writes each unit's
interface beside its generated C as Lisp data.

`src/compiler.x` owns compiler state, with its members under
`src/compiler/` for parsing, declarations, generated names, lifecycle, and
source files; `src/symbols.x` owns its symbol scopes. `src/diagnostics.x` owns structured errors. `src/utils.x` owns host-environment and process
helpers, including the C preprocessor process boundary. `src/frontend.x`
shares configured source stages and sequential unit lifetimes with internal
tools. `src/translation.x` owns the translation loop, inspections, workers,
and ordered diagnostics. `commands/build/` owns builds, runs, and script
caching. `src/main.x` dispatches those workflows to `x2c-build`; `src/cli.x` owns the option table, command selection, and help rendering.

Each feature entry lists the relevant parser, transforms, runtime code, and
tests so you can follow its complete implementation.

## Shared Lisp initialization

The compiler and `Lisp.new()` load the same `etc/init.xlisp`: the evaluator
primitives, macros, native bindings, and the standard algorithms (list
traversal, numeric wrappers, selectors, predicates, and pattern helpers).
The algorithms without callbacks are x2c functions in `lib/lisp-init.x`,
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
