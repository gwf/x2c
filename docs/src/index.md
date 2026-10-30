# The x2c Book

x2c extends C with dynamic values, collections, and compile-time code
generation. Use the features you need; keep ordinary C where it already
works. C headers, libraries, data layout, expressions, and native tools remain
available. x2c compiles to C, and its compiler and runtime are written in x2c.

This book explains how to use x2c and specifies its language and library.
[Install a native compiler](guide/installation.md) explains setup.

## What x2c adds

x2c adds these features to C:

- `Var` holds values and pointers with runtime type information, alongside
  ordinary static types.
- `String` provides immutable text with interpolation. Immutable `List`
  values share structure and support mapping, filtering, and folding;
  mutable `Array` and `Map` containers grow automatically and store `Var`s.
- `Symbol` provides compact named values without declaring an enum;
  `SymbolSet` gives those names an explicit order and indexing.
- `Iter` composes traversal operations, and `foreach` visits collections
  and `File` contents.
- `protocol` defines interfaces that concrete types explicitly adopt.
  Namespaced methods, inherited typedef methods, delegation, and static or
  dynamic dispatch let types share behavior while retaining C layouts.
- `Func` holds callable functions and capturing lambdas. Expression-bodied
  functions, dot methods, and call chains are also available.
- `Scope` and `Context` manage allocation lifetimes and isolated runtime
  state without garbage collection. Pools give immutable values nested
  lifetimes.
- `match` selects the first matching case for structured `List` data and
  exposes named captures as local variables.
- `Thread` runs work on native threads and returns results through `join`;
  `Mutex` coordinates access to shared mutable data.
- `Error` carries structured failures. `try`, `catch`, and `raise` handle
  them; `finally` and `defer` run cleanup when control leaves a block.
- `macro` expands to parsed source at compile time, and names a template
  declares stay private to each expansion. `Type`
  holes specialize code for concrete types, including typed collections.
  `Decorator` macros transform the expression or source item that follows.
  The optional [autodiff package](guide/autodiff.md) uses them to
  generate dual-number types from a `Type` hole and forward- and
  reverse-mode derivative functions with decorators.
- `import` brings packages into a local namespace, including wrapped C
  libraries and their x2c and Lisp bindings.
- `Lisp` evaluates code inside a running program, for DSLs and configuration.
  Compile-time code, by contrast, is ordinary x2c.

A program can use one feature and keep the rest in C.

## Reading the book

If you know C, most source will look familiar. The guide covers the
features that replace hand-written tagged unions, adapters, repeated
declarations, collection allocation, traversal, cleanup, and pattern
matching.

- The [language guide](guide/from-c.md) shows how to use x2c and when its
  features help.
- The [language reference](reference/language.md) states exact syntax and
  semantics.
- The [standard library](library/overview.md) describes the available modules
  and links to their API reference, generated from the source.
- [Compiler architecture](internals/architecture.md) explains the self-hosting
  implementation for readers who want to study or contribute to it.

The book describes implemented behavior. The optional `make doc-examples`
translates its x2c samples and compiles them to objects. `make doc-outputs`
also links and runs samples with expected output. The optional `make examples`
runs the showcase programs and checks their output.
