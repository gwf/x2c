---
title: Programming is Dead.<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
ideasIntro: "It's C. Plus three ideas."
ideas:
  - name: Just enough structure
    detail: "One data model and one lifetime rule, imposed on C, and the chores go: no `->`, no `free`, no `strcmp`, nothing between you and the algorithm. It is still C."
    code: |-
      foreach (String word in line.words()) counts[word] += 1;
  - name: Pieces that fit together
    detail: "With that structure in place, pattern matching, lambdas, threads, channels, jobs, files, HTTP, and your own types compose as easily as they do in Python, at C speed."
    code: |-
      routes.get("/api/notes", %!(HttpRequest req, HttpResponse res) =>
        list_notes(app, req, res));
  - name: A language that extends itself
    detail: "`meta` runs any function at compile time, a `macro` is a typed template over syntax, and the whole runtime, lambdas included, is available there. `try`, `match`, and `class` are written this way."
    code: |-
      meta static int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);
      static const int table[] = { $fib(10), $fib(20) };  // 55, 6765
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
