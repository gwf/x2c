---
title: Code is Magic
lede: "The compiler is written in x2c, and your program can call the compiler."
---

This is the third idea. Put `meta` in front of a function and it runs at
compile time, with the whole runtime available, lambdas included. A
`macro` is a typed template over parsed syntax, a decorator rewrites the
declaration after it, and `keyword` makes a macro a statement. A code
literal is a `List`, so the tools you use on data rewrite code.

The language extends itself with itself. `try`, `match`, `class`, and
lambdas are each one source file, built into the compiler and buildable
outside it the same way, and so is the compiler.
