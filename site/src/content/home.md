---
title: Programming is Dead.<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
featureIntro: "x2c is C with superpowers that you can selectively enable."
features:
  - name: Dynamic <br/> Values
    detail: "`Var` holds type-tagged values and pointers, with static typing and runtime introspection."
  - name: Immutable <br/> Strings
    detail: "Immutable `String`s support interpolation, text operations, safe sharing, and constant-time equality."
  - name: Symbols & <br/> Symbol Sets
    detail: "`Symbol`s compare in constant time without namespace collisions. `SymbolSet`s add enum-like order and indexing."
  - name: Immutable <br/> Lists
    detail: "Immutable `List`s share structure, compare in constant time, and compose through mapping, filtering, and folding."
  - name: Mutable <br/> Containers
    detail: "`Array`s and `Map`s store `Var`s, grow automatically, and have native syntax for all common operations."
  - name: Compound <br/> Literals
    detail: "Containers: `%[]`, `%{}`, `%()`. Strings: `%\"\"`. Bare names are data; `$` inserts expressions, `@` splices Lists."
  - name: Iteration <br/>& Loops
    detail: "Chained functional iterators and `foreach` over anything sequence-like, including `File`s and `Slice`s."
  - name: Object <br/>Orientation
    detail: "Namespaced methods, `typedef` inheritance, `protocol`s, delegation, and static or dynamic dispatch."
  - name: Functional <br/>Tools
    detail: "Lambdas like `%!() => 42`, closures, expression-bodied functions, dot methods, and call chains."
  - name: Managed <br/> Lifetimes
    detail: "`Scope` and `Context` manage allocation lifetimes without garbage collection. Immutable values use pools with nested lifetimes."
  - name: Pattern <br/>Matching
    detail: "`match` compares a `List` against patterns; named bindings extract matched values as local variables."
  - name: Threads & <br/>Mutexes
    detail: "`Thread` runs work on native threads and returns results through `join`. `Mutex` coordinates access to shared mutable data."
  - name: Exception <br/>Handling
    detail: "`try`, `catch`, and `raise` handle errors; `finally` and `defer` run cleanup as control leaves a block."
  - name: Compile-time <br/> Generics
    detail: "`Type` holes generate specialized code with no runtime overhead, including typed `List`s and optimized packed `Array`s and `Map`s."
  - name: Imports &<br/> Namespaces
    detail: "C headers and libraries can be wrapped with x2c and Lisp bindings, then `import`ed without symbol collisions."
  - name: Compile-time <br/> Macros
    detail: "Hygienic, typed `macro`s generate parsed x2c syntax at compile time, from expressions to entire translation units."
  - name: Semantic <br/> Decorators
    detail: "`Decorator`s transform the expression or source item that follows. Use them to add checks, trace calls, or define new control forms."
  - name: Lisp <br/>Inside & Out
    detail: "`$()` runs Lisp at compile time; `Lisp` runs it inside your program. Both use the same bytecode interpreter."
---

x2c is a quirky little language that makes programming fun and a bit weird. It
has legitimate applications, presumably, but is more about coding for the joy of
it. Some users of x2c report heightened expressiveness, a sense of universality,
with a touch of transcendence. Be sure to drink plenty of water.

x2c is C with batteries and without the bullshit.
It extends C and compiles to C, keeping C's
native performance, tooling, ecosystem, and portability while adding the
conveniences of a modern language. x2c extends C's syntax with a few new
keywords, but the real magic is in the `%` and `$` sigils, which let you write
code that combines static types, dynamic values, and compile-time computation.

x2c's main features are summarized in the table on the right. Everything is
optional and works with plain C as well. Hence, you can take existing C code and
adopt x2c capabilities incrementally. The [C foundation](docs/reference/language.html#c-foundation) and
[host preprocessing notes](docs/reference/language.html#host-preprocessing) explain the boundaries.

[Packages](#packages) bring SQLite, JSON, HTTP, and graphics into the same
style of code. See what you can build with one example from each.

The compiler, library, and runtime are all written in x2c, with no third-party
dependencies. You can read the source to learn the language, then change the
language by editing the source. The [repository counts](#source) give a sense
of its size.

At this point, you may be wondering: why learn a new programming
language, let alone create and release one, in a post-AI world?
Fair question. **Programming is not about making computers do things; it's
about helping brains think things.** Now, more than ever, the best reason to
code is to rewire your brain. So if programming is more than a career to
you---if you code for *love*, *power*, or *magic*---try a bit of x2c.
