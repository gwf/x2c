# The x2c Book

x2c extends C with dynamic values, collections, and compile-time code
generation. Use the features you need; keep ordinary C where it already
works. C headers, libraries, data layout, expressions, and native tools remain
available. x2c compiles to C, and its compiler and runtime are written in x2c.

This book explains how to use x2c and specifies its language and library. For a
short introduction and installation instructions, follow the links above.

## What x2c adds

Start with C types and calls, then add what the program needs:

- `Var` holds values and pointers with runtime type information, alongside
  ordinary static types.
- `String` provides immutable text with interpolation. Immutable `List`
  values share structure and support mapping, filtering, and folding;
  mutable `Array` and `Map` containers grow automatically and store `Var`s.
- `Symbol` provides compact named values without declaring an enum;
  `SymbolSet` gives those names an explicit order and indexing.
- `Iter` composes traversal operations, and `foreach` visits collections,
  `File` contents, and `Slice` sequences.
- `protocol` defines interfaces that concrete types explicitly adopt.
  Namespaced methods, inherited typedef methods, delegation, and static or
  dynamic dispatch let types share behavior while retaining C layouts.
- `Func` holds callable functions and capturing lambdas. Expression-bodied
  functions, dot methods, and call chains keep composed operations brief.
- `Scope` and `Context` manage allocation lifetimes and isolated runtime
  state without garbage collection. Pools give immutable values nested
  lifetimes.
- `match` selects the first matching case for structured `List` data and
  exposes named captures as local variables.
- `Thread` runs work on native threads and returns results through `join`;
  `Mutex` coordinates access to shared mutable data.
- `Error` carries structured failures. `try`, `catch`, and `raise` handle
  them; `finally` and `defer` run cleanup when control leaves a block.
- `macro` generates hygienic, parsed, typed source at compile time. `Type`
  holes specialize code for concrete types, including typed collections.
  `Decorator` macros transform the expression or source item that follows.
- `import` brings packages into a local namespace, including wrapped C
  libraries and their x2c and Lisp bindings.
- `Lisp` evaluates code inside a running program; compile-time Lisp uses the
  same interpreter to compute values and generate syntax during translation.

Using one feature does not require converting the rest of the program to a
new object model.

## Reading the book

If you know C, most source will look familiar. The guide concentrates on the
places where x2c replaces work you would otherwise do by hand: tagged unions,
adapters, repeated declarations, collection allocation, traversal, cleanup,
and pattern matching.

- The [language guide](guide/from-c.md) shows how to use x2c and when its
  features help.
- The [language reference](reference/language.md) states exact syntax and
  semantics.
- The [standard library](library/overview.md) describes the available modules
  and links to their API reference, generated from the source.
- [Compiler architecture](internals/architecture.md) explains the self-hosting
  implementation for readers who want to study or contribute to it.

The book describes implemented behavior. Its x2c samples are translated and
checked for valid C syntax. `make examples` also runs the showcase programs
and checks their output.
