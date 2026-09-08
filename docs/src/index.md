# The x2c Book

x2c extends C with dynamic values, collections, and compile-time code
generation. Use the features you need; keep ordinary C where it already
works. C headers, libraries, data layout, expressions, and native tools remain
available. x2c compiles to C, and its compiler and runtime are written in x2c.

This book explains how to use x2c and specifies its language and library. For a
short introduction and installation instructions, follow the links above.

## What x2c adds

Start with C types and calls, then add what the program needs:

- `Var` holds dynamic values; `String`, `List`, `Array`, and `Map` hold text
  and collections. `Func` and `Lisp` let programs call and evaluate code.
- `Iter` traverses values, and `Match` takes structured data apart. `Scope`
  manages allocation lifetimes; `Context` and `Thread` isolate runtime state;
  `Error` records and propagates failures.
- `translate` produces C for an existing build. `build`, `run`, and
  `bootstrap` also handle native compilation and execution.
- `protocol`s adapt concrete types to explicitly adopted interfaces. Macros
  generate parsed, typed source at compile time.

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
