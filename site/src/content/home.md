---
title: Programming is Dead.<br/>Long Live Programming.
kicker: "x2c is a language for people who love to code."
---

Every programming language is built around a few values that determine what is
easy or awkward to express. Python values readability and comes with batteries included. C values a small and fast
mapping to the machine. Lisp values code and data being the same. Languages are
opinionated because their goals conflict, and each one picks its priorities.

x2c is a quirky little language that would rather not pick. Static or dynamic,
mutable or immutable, compile-time or run-time, managed or unmanaged: every option
stays available. x2c is picky about one thing only, which is that it all
stays one small language. The same code works in every mode, from single bits
up to whole systems. You can change your mind or
your paradigm without changing languages.

All of which makes x2c sound like a language with no values. It has three:
*love*, *power*, and *magic*, and we know how that sounds.
Nonetheless, see the panel for the values translated into code.

Under the hood, x2c is a strict superset of C that compiles to C, so everything
stays close to native representations and works with the entire C ecosystem. If
you know C, you already write x2c.

<!-- example: Love -->

Love is C made readable. Simple things are simple. A handful of types (`Var`,
`String`, `Symbol`, `List`, `Array`, `Map`, and `File`), their literal syntax,
`foreach` over any container, and a rich API of methods quietly remove much of
the bullshit that makes C painful.

```x2c
~int main(void) {
List words = %("to" "be" "or" "not" "to" "be");
Map counts = {};
foreach (String word in words)
  counts[word] += 1;
~return 0;
~}
```

<!-- example: Power -->

Power is C made composable. Complex things are possible. Iterators, `match`,
scopes, exceptions, and threads all work with the built-in types and with each
other, and the protocols behind those types are open to your own. No framework
is needed to hold it together. The pieces are small, and they compound.

<!-- ignore: Illustrative pipeline; count_file and add_counts are application functions. -->
```x2c,ignore
Map totals = Path.new("src").walk().filter(Path.is_file)
  .parallel_map(count_file, 4).foldl({}, add_counts);
```

<!-- example: Magic -->

Magic is C made reflective. It insists upon itself. Macros and decorators
rewrite the program's syntax as it compiles, meta functions run ordinary x2c at
compile time, and the compiler is itself written in x2c. When a problem resists,
you can change the language instead.

<!-- ignore: Decorator usage assumes application-provided mutex, balance, and deposit. -->
```x2c,ignore
macro Decorator $do_with_lock(Stmt $body, Expr $lock) { {
  Mutex held = $lock; held.lock(); defer held.unlock();
  $body
} }
keyword with_lock $do_with_lock;

with_lock (mutex) balance += deposit;
```

<!-- closing -->

Why bother? Because **programming is not about making computers do things;
it is about helping brains think things**, and x2c is a language for thinking in code.
Some users report heightened expressiveness, a sense of universality, and a
touch of transcendence. Be sure to drink plenty of water.
