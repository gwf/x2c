# Release Notes

Each section summarizes what changed for a user of the compiler, runtime,
commands, and packages since the previous release.

## 0.16.0 (unreleased)

Compile-time code is ordinary x2c: the compiler no longer evaluates Lisp,
and `$(...)` builds an evaluated List. The release adds temporary
assignments with `with`, expression aliases, rest parameters, pattern
conditions, Channels and tasks, networking, testing, and the `x2c lsp` and
`x2c test` commands.

### Upgrading from 0.15.1

- `$let(place, value) body` becomes `with (place = value) { body }`; a body
  without braces needs them.
- `with expression as name { ... }` becomes
  `alias expression as name { ... }`, and `with expression { ... }` becomes
  `alias expression { ... }`.
- A compile-time Lisp form such as `$(import "file.xlisp")` becomes a
  `meta` function called with `$helper(...)`; `$(...)` in code now builds
  an evaluated List.
- An object or function named `expand` can be declared but not read or
  called; rename it.
- `%<<a b c>>` becomes `%<a b c>`.
- `array.find(value)` and `array.indexof(value)` become `array.index(value)`.
- `Scope.retain()` and `Scope.release()` become `Scope.open()` and
  `Scope.close()`. The `Scope.up` field, which linked a region to the region
  opened after it, is removed and has no replacement.
- `text.try_long(&value)` becomes `text.try_long(value)`, and likewise for
  `String.try_double` and `Symbol.try_new`.
- A `List` passed as the values of `String.format`, `Logger.log`, or the
  `log_*` functions becomes `@values`, or separate arguments.
- `$switch` becomes an ordinary `switch` with a block and `break` per case.
- `x2c editor` becomes `x2c lsp`.
- A `List`, `Array`, `Map`, or `Symbol` passed to a printf-family `%s` is an
  error; pass its `.str()` or `.repr()`, or pass a `Var`.
- `x2c repl` is not installed by releases; build it in a checkout with
  `make commands`.

### Language

- The compiler no longer evaluates Lisp. The compile-time `$(...)` and
  `@(...)` Lisp forms, including `$(import "file.xlisp")`, are removed.
  Such a form at file scope reports
  `an evaluated collection is an expression, not a top-level form`.
  Write the computation as a `meta` function and call it with
  `$helper(...)` or `@helper(...)`, and use the operations in `meta.x` by
  their x2c names, such as `x2c_ident` and `Code.binding_spelling`, in place
  of the Lisp names `x2c.ident` and `x2c.literal.string`. See
  [Compile-time calls and operations](language.md#compile-time-calls-and-operations).
- Runtime Lisp is unchanged: `Lisp.new`, `lisp.eval`, and `.xlisp` files work
  as before, and `$lisp.bind`, `$lisp.binding`, and `$lisp.install` keep
  their behavior. A `meta` function that uses Lisp runs in the project
  helper; a native module the compiler loads no longer receives Lisp. See
  [Runtime Lisp](language.md#runtime-lisp).
- `$(...)` now builds a List from evaluated expressions, `@(...)` splices a
  List or Map into a literal or call, and `${key: value}` builds a Map whose
  bare identifier keys are evaluated. See
  [Evaluated Lists and Maps](language.md#evaluated-lists-and-maps).
- A final `List @name` parameter packs the trailing call arguments into one
  List, and `List.new(a, b, c)` builds a List the same way. See
  [List rest parameters](language.md#list-rest-parameters).
- A final `Map @name` parameter receives `key: value` call arguments as a
  Map, and `@map` passes a Map through. See
  [Map rest parameters](language.md#map-rest-parameters).
- `with (place = value) { ... }` assigns for the block and restores the
  old value on every exit, replacing `$let`. See
  [Temporary assignments with `with`](language.md#temporary-assignments-with-with).
- `alias name to expr;`, also written `alias expr as name;`, substitutes
  an expression for a name until the end
  of its scope, `static alias` does so at file scope, and `unalias name;`
  ends an alias early. The old `with` alias form is removed. See
  [Expression aliases with `alias`](language.md#expression-aliases-with-alias).
- `subject ~= pattern` is a condition that binds the pattern's names where
  it holds, so a one-case `match` reads as an `if`. See
  [Pattern conditions](language.md#pattern-conditions).
- Reference parameters: a `struct T` lvalue satisfies a `T` reference to
  that struct; a pointer, `NULL`, or `0` for a required reference, a
  pointer value where a pointer to its type is declared, and an unchecked
  optional reference forwarded to a required one are compile errors. An
  optional reference is proven through `!`, `&&`, `||`, and `?:`. See
  [Reference parameters](language.md#reference-parameters).
- `match` compiles most patterns to inline tests instead of runtime pattern
  machinery; three pattern kinds still use the runtime matcher. Behavior is
  unchanged. See [Pattern Matching](../guide/match.md).
- The `$switch` decorator is removed from `system-macros.x`. Write an
  ordinary `switch` that gives each case run its own block and `break`.
- `--cpp` on `translate`, `build`, and `run` expands the C macros x2c can
  see and decides `#if` groups before parsing, for existing C whose macros
  supply grammar. It is off by default: ordinary translation still leaves
  macro uses to the C compiler and hides only `#if 0` and impossible host
  arms, as 0.15.1 did. Macro arguments follow C99, so only parentheses group
  commas, and a comma inside `[]` or `{}` separates arguments. With `--cpp`,
  `-D` and `-U` also define macros for the expansion, and `--dump-tokens`
  prints the expanded tokens. Module, import, and `meta` constructs inside C
  macros are not discovered. See
  [Optional C macro expansion](language.md#optional-c-macro-expansion).
- A declaration prefixed by an object-like attribute macro keeps that macro
  in its unit's own C. With `#define WEAK __attribute__((weak))`,
  `WEAK int weak_value = 5;` stays as written, so the C compiler applies the
  attribute, and the generated header declares `extern int weak_value;`. A
  typedef keeps a leading attribute, written or through such a macro, in its
  C and its header. A function-like wrapper such as `PUBLIC(const char *)`
  still contributes only its type. See
  [C headers and native declaration
  macros](language.md#c-headers-and-native-declaration-macros).
- `SymbolSet` literals are written `%<a b c>`; the 0.15.x `%<<a b c>>`
  spelling is an invalid token. An unescaped `>` closes the literal unless
  it belongs to a quoted or angle-form member, so `%<">" ">=" ">>">` holds
  three operator Symbols, and `x %<foo>` after an operand is still modulo
  by `<foo>`. See [Symbol sets](language.md#symbol-sets).
- `associated`, `catch`, `delegate`, `finally`, `import`, `protocol`,
  `raise`, `threaded`, and `try` are contextual keywords: outside their
  keyword forms they can name objects, functions, parameters, fields,
  typedefs, and labels. `defer` remains reserved in expressions, and the C
  keywords remain reserved. See
  [Contextual keywords](language.md#contextual-keywords).
- A decorator can take a `Macro` target, and a decorator can return another
  decorator, which then consumes the next source target. `expand ROWS`
  before a macro applies that macro once per row of a compile-time List,
  placing the output by the macro's result kind. `expand` is a predefined
  keyword alias, so an ordinary object or function can no longer be named
  `expand`. See [Mapping rows with `expand`](language.md#mapping-rows-with-expand)
  and
  [Decorators that return decorators](language.md#decorators-that-return-decorators).

### Library

- String slicing with a zero step now raises `<bad-arg>`, including on an
  empty String. It previously returned the empty String. Array, typed Array,
  List, and String now reject zero steps consistently.
- Array value search is now `index(value)`, including on typed Arrays. It
  returns the first equal element's position, or `-1`. `find` now takes a
  predicate and returns the first accepted element as a `Var`, or `void`.
  The old `indexof` name is removed, and there are no compatibility aliases.
  The native signatures change, so rebuild native code that calls them. List
  and Iter `find` keep their contracts.

  | 0.15.1 | Now |
  | --- | --- |
  | `array.find(value)`, returning an index | `array.index(value)` |
  | `array.indexof(value)` | `array.index(value)` |
  | `int Array_find(Array, Var)` | `int Array_index(Array, Var)` |
  | `int Array_indexof(Array, Var)` | removed |
  | none | `Var Array_find(Array, Func)` |

- `Task.run` runs zero-argument jobs cooperatively on the calling native
  thread, using Channels. Results keep ordinary ownership, and every
  exit finishes all job cleanup. Blocking native calls block the batch. The
  guarded-stack backend supports macOS and Linux on arm64 and x86_64. See
  [Task.run](../library/modules/task.md#Task.run) and
  [Run Channel jobs on one native thread](../guide/contexts-and-threads.md#run-channel-jobs-on-one-native-thread).
- `Scope.retain` and `Scope.release` are renamed to `Scope.open` and
  `Scope.close`; both still return `void`. `Scope.up` is removed without a
  replacement. The native function names and public Scope layout change, so
  regenerate C and rebuild native code that uses Scope. Pool's retain/release
  operations and `Pool.up` are unchanged.
- Boxed `long double` identity, content hashes, and total ordering exclude
  x87's six ABI padding bytes. The ten value bytes still preserve precision,
  signed zero, and NaN payload distinctions. Hash values change on x87
  targets; recompute stored or precomputed hashes when upgrading. Other
  long-double formats keep their existing payload widths.
- `Map`, the typed Maps, and `Pool` tables share one grouped hash storage:
  sixteen one-byte controls per group, compared at once, with full hashes
  kept beside them for `Map` and `Pool`. Public methods, container layouts,
  capacity, ownership, and custom hash and equality behavior are unchanged;
  traversal order changes, as the existing contract allows, so a program
  that depended on the previous order must sort. See
  [Working with Maps](../guide/collections.md#working-with-maps) and
  [Packed typed Maps](../guide/collections.md#packed-typed-maps).
- `String.try_long`, `String.try_double`, and `Symbol.try_new` take their
  result through an optional reference, `T &?out`, instead of `T *out`.
  Pass the variable itself, as in `text.try_long(value)`; `&value` is now a
  type error, and `NULL` still discards the result.
- `x2c_normalize_slice` takes `int &start` and `int &stop`, and the
  `x2c_match_*` capture and site functions take their outputs as `T &?`
  references, as do `MatchLease.plan`, `MatchLease.release`, and
  `MatchCaptureBuffer.has`. x2c callers pass the object instead of its
  address; the generated C prototypes still take pointers.
  `x2c_normalize_slice` no longer checks its bounds for null.
- `String.format`, `Logger.log` and its level methods, `log_event`, and the
  `log_*` functions take their values as a final `List @fields` parameter,
  as does the sqlite package's `Prepared.bind`. Pass separate arguments, or
  splice an existing List with `@values`; a bare List argument is now one
  value.
- `Channel` in `lib/channel.x` passes `Var` messages between threads, with
  rendezvous, bounded, or unbounded capacity and an explicit close. See
  [Channels](../guide/channels.md).
- The optional `net.x` adds blocking TCP `Socket`s and `Listener`s, and
  `http.x` adds requests, responses, a `Router`, and a worker-pool
  `HttpServer`. See [Sockets and HTTP](../guide/networking.md).
- The optional `test.x` registers tests and supplies assertions and a test
  program entry, and `derive.x` generates Map, JSON, equality, argument,
  and row mappings from struct fields. See [Testing](../guide/testing.md)
  and [Deriving Record Mappings](../guide/deriving-records.md).
- The optional `time.x`, `random.x`, `encoding.x`, and `url.x` add clocks
  and calendar time, seedable random values and UUIDs, base64, hex, and
  percent encodings, and URL parsing. See
  [Time, Random Values, and Encodings](../guide/time-random-encodings.md).
- `Code.native_signature` returns the `Func` signature of a function for
  compile-time code.
- `Type.spelling` returns a type as a declaration spells it without a name,
  such as `int *` or `int (*)(int, char *)`. See
  [Type.spelling](../library/modules/type.md#Type.spelling).
- A C string passed through a `Func` is boxed as a `String`, so `String`,
  native pointer, and `Var` parameters all accept it.
- `Thread.finish_all` no longer prints a cleanup diagnostic during an error
  unwind when every worker was joined.

### Commands and packages

- The experimental `x2c bind` writes the mechanical part of a new package
  from a C header: handle types, forwarded methods, and `Cleanup` for paired
  release calls. It is available in checkout builds and not installed. See
  [Commands](cli.md#commands).
- The x2c home is now marked by `etc/compiler-prelude.x`, which holds the
  builtin macros, in place of `etc/compiler-sdk.xlisp`.
- `x2c lsp` serves editors over the Language Server Protocol and replaces
  the 0.15.1 `x2c editor` command. Normal installations include it, and the
  VS Code extension in `etc/vsc-extension` starts it. See
  [Language server](cli.md#language-server).
- `x2c test` finds and runs a project's test programs, which use `test.x`.
  Normal installations include it. See [Testing](../guide/testing.md).
- `x2c repl` is now a native library playground. `:load` builds a program
  from C or x2c sources, headers, and native libraries with the ordinary
  compiler. Each submission compiles natively and runs in a supervised
  worker process, so prompt and library objects share native pointers and
  layouts. The playground replaces the interpreted subset and its Lisp
  evaluation. The prompt rejects `meta`, macro, protocol, and `import`
  declarations, which a loaded source file supplies. The command is
  experimental and checkout-only: `make install` and release payloads no
  longer install it. See [Library Playground](../guide/repl.md).
- Each playground session start removes the entries under `repl/` in the
  cache root whose recorded program source no longer exists, as script
  builds do under `scripts/` and `runs/`. `Compiler.prune_cache` in the
  compiler API holds that rule.
- `x2c lint` and `x2c graph` are experimental: a checkout builds them with
  `make commands`, and installations do not include them.
- A warning prints as `file:line:column: warning: code: message`, so it is
  distinct from an error. See
  [Compiler diagnostics](cli.md#compiler-diagnostics).
- The sqlite package joins the checked packages.

### Fixed defects

- A printf-family `%s` with a static format prints the empty `String` as no
  text; it printed `(null)`.
- A `List`, `Array`, `Map`, or `Symbol` at a printf-family `%s` is a
  compile-time error; it was passed as a raw pointer and printed garbage or
  crashed.
- Diagnostics spell types as declarations do, such as `int *` and
  `double (int)`, name the method, function, or macro in argument-count
  errors, and omit expansion notes that pointed into the compiler's own
  definitions.
- Regex matching checks the stack floor for sequential and nested groups,
  so excessive matching recursion raises a catchable size-limit error.
- Calls through a pointer to a function typedef now convert arguments as
  calls through a function-pointer typedef do, including boxing into `Var`.
- An array dimension constructed by a macro can contain another expression
  macro; the ordinary binder resolves it before interface emission.
- Typed callback adapters retain pointee qualifiers in their result checks
  and generated calls. A const result cannot become a mutable pointer result.
- Region diagnostics now follow receiver returns from `Array.update_n`,
  `Map.update_n`, and `Map.merge_with`, including compile-time definitions.
- A `~=` pattern condition whose false branch continues with `else if` now
  places that continuation inside a block, so the generated C keeps the
  branch and compiles without a dangling-else warning.
- With `--cpp`, a macro whose name is a keyword spelling expands source
  tokens only; the same spelling stored as a literal atom, as in `%(if)`,
  is left intact.
- A generated protocol owner whose signature conflicts with the adopted
  protocol is reported at the adoption, with the expected and actual
  signatures, instead of as a bare argument-count error.
- With `--cpp`, collection decides a header's later `#ifndef` arm as a
  linear reading of the header does, even when an `#include` sits inside an
  earlier undecided group such as `#ifdef __APPLE__`.
- With `--cpp`, `#if` reads a character constant as the C compiler does, so
  `'\0' == 0` holds and `'\xff'` is negative; multi-character constants,
  shift counts outside 0 to 63, and `LONG_MIN / -1` stay undecided.
- An arm that C never takes, such as the `#else` of `#ifndef __cplusplus`,
  stays hidden after an `#include` earlier in its group, so C++ text there
  no longer fails collection.
- A playground candidate whose worker fails while starting reports
  `session unchanged` and keeps the active session.
- `:reload` after loading a manifest rebuilds the selected roots once
  instead of adding the manifest's inputs to them again.

## 0.15.1 (2026-10-17)

A patch release of 0.15.0. Existing installations upgrade in place; no
packages need rebuilding.

- An uncaught error prints one line naming the error, the raising function
  and location, and its details, then aborts with the same status. The
  full logger event remains available with `X2C_DEBUG` or a `<log>` policy.
  See [Handlers and policy](../guide/exceptions.md#handlers-and-policy).
- `$auto` on a local that is already managed is a compile-time error
  instead of a crash at scope exit.
- The REPL continues a list literal across lines, and code it loads
  boxes classes, expands its own meta functions, and calls protocol
  defaults as an ordinary build does.
- REPL input and compiled prompt functions can call C's `printf` and
  `puts`.
- The book gains this release notes page, and the repository gains a
  security policy, a pull request template, and a bug report template.

## 0.15.0 (2026-10-17)

Releases ship for macOS arm64 and x86_64 and Linux aarch64 and x86_64, with
the book as a PDF beside the archives.

### Language

- `meta` functions run ordinary x2c during translation. A macro body calls
  one with `$helper(...)`, passes constants or captured syntax, and inserts
  the code it returns. `meta.x` supplies the `Code` and `Type` operations
  for inspecting and building code. See
  [Meta Functions](../guide/meta-functions.md) and
  [Generating Code](../guide/generating-code.md).
- Macro values: a macro can select, apply, and collect cases as values,
  and typed quotations with expression holes build code with its type.
- `Stmt` macros accept an expression body, and a macro call may begin with
  a dotted name.
- Module blocks split one translation unit across a directory. The new
  `module` storage class is visible in every member file; `static` stays
  private to its file.
- Indentation syntax: a `.xp` file, or `#pragma indent` in a `.x` file,
  groups statements by indentation without braces or semicolons. See
  [Indentation Syntax](../guide/indentation.md).
- `raise` is a statement head, `catch` accepts patterns as codes, and a
  variable may supply a `raise` code.
- Optional reference parameters, GNU statement expressions, `threaded`
  thread-local storage, and the contextual `in` membership operator.
- A `switch` whose selector is a `String` selects its case by content.
- `class` types gain `alloc` and a refusing `init`, and `init` takes
  constructor arguments.
- Twelve language features moved out of the compiler kernel into
  components under `src/components/`; their behavior is unchanged.

### Library

- `lib/regex.x` adds regular expressions over the bytes of a String, and
  every `x2c script` can use them.
- `lib/diff.x` computes line differences between two texts.
- The runtime's canonical pool operations moved from `List` to `Pool`.
- `Var.truth` replaces `Var.truthy`; `List.reduce`, `Array.reduce`, and
  `Iter.reduce` are removed in favor of `Iter.foldl`.
- `FileReadStatus` is a `Symbol`, `<data>`, `<eof>`, or `<error>`, instead
  of an enum of `FILE_READ_DATA`, `FILE_READ_EOF`, and `FILE_READ_ERROR`.
  This changes the native type of the raw `File` readers' results.
- Compile-time Lisp gains tail calls and a bounded call depth.

### Commands and packages

- `x2c new` creates a starter project that builds and runs.
- `x2c repl` is a shipped command with line editing, grammar-aware and
  semantic completion, and named inspection of session values. It
  evaluates a supported subset of the language. See
  [Experimental REPL](../guide/repl.md).
- Package management, the editor adapter, and project creation are
  external commands under `libexec/x2c/`. `x2c lint` and `x2c graph` are
  shipped as experimental.
- Packages record native arguments in `<name>.native.rsp` instead of
  `<name>.link`. Rebuild source packages and replace native bundles.
- Automatic differentiation moved from the runtime to the optional
  `autodiff` package; `import "autodiff"` supplies its types and macros.
- The SQLite package renames `Statement` to `Prepared` and
  `Var.statement` to `Var.prepared`.
- Every package manages its handles with `$auto`, so connections, loops,
  images, documents, and terminals release at scope exit.
- The C* verification package is removed.

### Documentation

- The book adds the [x2c Syntax Map](../guide/x2c-syntax-map.md) for C
  readers, the [syntax specifications](syntax/index.md) with a source
  grammar and lexical rules, [The Region Model](../guide/regions.md), and
  chapters for meta functions, generating code, the REPL, and indentation.
- The language reference was corrected against the implementation and
  its repeated rules removed.
- The public site at [x2c-lang.dev](https://x2c-lang.dev/) carries the
  book under `/docs/`.

### Fixed defects

- A `return` inside a `defer` or `finally` body leaves its exception frame
  before transferring, so a later `raise` in the caller is caught.
- Macro bindings retained across package builds, nested empty unit
  macros, quotation members and splices, and template members in
  anonymous aggregates expand correctly.
- Parameter redeclaration inside callable bodies and the author-binding
  `extern` regression are fixed.
- Constructed raw string segments, nested string literals inside list
  literals, and negative percent literals in every radix are read as
  written.
- Pointer arithmetic over pointer typedefs and casts to template typedefs
  type correctly.
- Project meta payloads, include handling, the failure cache, and host
  flags are repaired for package builds.
