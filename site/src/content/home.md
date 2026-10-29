---
title: Programming is Dead.<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
ideasIntro: "It's C. Plus five ideas."
ideas:
  - name: One value
    detail: "`Var` is an eight-byte tagged word that holds anything and knows what it holds. Collections store it, `%s` prints it, typed C boundaries convert it."
    follows: "`String`, `List`, `Array`, `Map`, `Symbol`, lambdas, `is`, and a `printf` that just works."
  - name: Two kinds of data
    detail: "`String`, `List`, and `Symbol` are canonical values: equal content is one object. `Array` and `Map` are objects with identity."
    follows: "Constant-time `==`, free sharing, `===`, and anything as a `Map` key."
  - name: Lifetime by region
    detail: "`auto`, `Scope`, and `defer` free memory when a statement, loop body, or function leaves. No collector. No `free`."
    follows: "`Scope`, `Context`, pools, `class` allocation, and cleanup when an exception unwinds."
  - name: Code is a List
    detail: "`%(...)` quotes it, `match` and `~=` take it apart, `$` and `@` put it back together. Data, pattern, template, and syntax are one `List`."
    follows: "`match`, destructuring, `Error` causes, command lines, and runtime `Lisp`."
  - name: Functions run in the compiler
    detail: "`meta` makes any function callable at translation time. Macros and decorators are typed templates that hand captured code to meta functions."
    follows: "Generics, `class`, `$derive`, `$test`, autodiff, your own `keyword`s, and a self-hosted compiler."
---

x2c is a quirky little language that makes programming fun and a bit weird.
Some users report heightened expressiveness, a sense of universality, and a
touch of transcendence. Be sure to drink plenty of water.

Under the hood it is a strict superset of C that compiles to C. Your headers,
structs, libraries, build, and debugger all keep working. Every feature is
optional, so you can adopt x2c one file at a time in code you already have.
The compiler, the runtime, the language server, and the test runner are all
written in x2c, and you can read every line.

It looks like a lot. It isn't. Learn the five ideas on the right and the
rest of the language is just consequences. **Programming is not about making
computers do things; it's about helping brains think things.** If you code
for *love*, *power*, or *magic*, this one is for you.
