---
title: Programming is Dead,<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
ideasIntro: "It's C. Plus three ideas."
ideas:
  - name: C without the rough edges
    detail: "Every rough edge of C is gone and nothing good is lost: C's speed, portability, and ecosystem stay. What you get back is the list you associate with interpreters: one value type, strings and collections with methods, interpolation, destructuring, lambdas, pattern matching, and memory freed by scope."
    code: |-
      foreach (String word in line.words())
        counts[word] += 1;
  - name: Pieces that compound
    detail: "Classes, protocols, modules, and packages build on one another, so a server, a job pipeline, or a threaded tool is a few lines: written as fast as in Go, Python, or JavaScript, and running at C speed."
    code: |-
      routes.get("/api/notes",
        %!(HttpRequest req, HttpResponse res) =>
          list_notes(app, req, res));
  - name: A language that extends itself
    detail: "`meta` runs any function at compile time and a `macro` is a typed template over syntax, with the whole runtime available there. `try`, `match`, and `class` are written this way, and so is the compiler."
    code: |-
      meta static int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);
      macro Expression $minutes(Expr $hours) => $hours * 60;
      static const int table[] = { $fib(20), $minutes(1 + 1) };  // 6765, 120
---

x2c is a quirky little language that makes programming fun and a bit weird.
Some users report heightened expressiveness, a sense of universality, and a
touch of transcendence. Be sure to drink plenty of water.

It is a strict superset of C that compiles to C. Your headers,
structs, libraries, build, and debugger all keep working. Every feature is
optional, so you can adopt x2c one file at a time in code you already have.
The compiler, the runtime, the language server, and the test runner are all
written in x2c, and you can read every line.

It looks like a lot. It isn't. Learn the three ideas on the right and the
rest of the language follows from them. **Programming is not about making
computers do things; it's about helping brains think things.** If you code
for *love*, *power*, or *magic*, this one is for you.
