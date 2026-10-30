---
title: Programming is Dead.<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
featureIntro: "Superpowers for C, each one optional."
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
    detail: "Arrays, Maps, Lists, and interpolated Strings have literal syntax, so nested data reads the way you wrote it. Splice values and expressions in anywhere."
  - name: Iteration <br/>& Loops
    detail: "Chained functional iterators and `foreach` over anything sequence-like, including `String`s, `Map`s, `File`s, and `Channel`s."
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
  - name: Meta & <br/>Lisp
    detail: "`meta` functions run x2c at compile time; `Lisp` embeds a recursive Lisp evaluator in your running program."
---

x2c is a quirky little language that makes programming fun and a bit weird. It
has legitimate applications, presumably, but is more about coding for the joy of
it. Some users of x2c report heightened expressiveness, a sense of universality,
with a touch of transcendence. Be sure to drink plenty of water.

Under the hood, x2c is a strict superset of C that compiles to C. You keep C's
native performance, tooling, ecosystem, and portability, and gain the conveniences
of a modern language. A few new keywords extend C's syntax, but the real magic
is in `meta`: functions that run while the compiler builds your program as well
as in the finished one, computing values and writing code.

Everything is optional and works with plain C, so you can adopt x2c one feature
at a time in code you already have.
The compiler, library, and runtime are themselves written in x2c, with no
third-party library dependencies. Read the source to learn the language; edit
it to change the language. The [repository counts](#source) show how much there
is to read.

Why learn a new language, let alone release one, in a post-AI world?
Fair question. **Programming is not about making computers do things; it's
about helping brains think things.** The best reason to code is still to
rewire your brain. So if programming is more than a career to
you---if you code for *love*, *power*, or *magic*---try a bit of x2c.
