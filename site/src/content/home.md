---
title: Programming is Dead.<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
ideasIntro: "It's C. Plus four ideas."
ideas:
  - name: Still C, with less of it
    detail: "Every feature is sugar that lowers to C you can predict. Most programs never touch a pointer."
    follows: "methods on any type, `class`, protocols, and C you can read."
  - name: One data model, two speeds
    detail: "`Var` is an eight-byte word that holds any value and its type. A `String` is still a C string, so every value is dynamic and native at once."
    follows: "collections that hold anything, `is`, and a `printf` that prints any of them."
  - name: Lifetime by scope
    detail: "`String`, `List`, and `Symbol` are shared and immutable, so equal content is one object. Everything else is allocated in a scope and freed when the scope ends. No collector, no `free`."
    follows: "constant-time `==`, free sharing across threads, `auto`, and `defer`."
  - name: Its own metalanguage
    detail: "The compiler is user space. A code literal `%(...)` is a `List`, and `meta` runs any function at compile time."
    follows: "try, match, lambdas, `keyword`s, and a compiler that compiles itself."
---

x2c is a quirky little language that makes programming fun and a bit weird.
Some users report heightened expressiveness, a sense of universality, and a
touch of transcendence. Be sure to drink plenty of water.

It is a strict superset of C that compiles to C. Your headers,
structs, libraries, build, and debugger all keep working. Every feature is
optional, so you can adopt x2c one file at a time in code you already have.
The compiler, the runtime, the language server, and the test runner are all
written in x2c, and you can read every line.

It looks like a lot. It isn't. Learn the four ideas on the right and the
rest of the language follows from them. **Programming is not about making
computers do things; it's about helping brains think things.** If you code
for *love*, *power*, or *magic*, this one is for you.
