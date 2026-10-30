---
slug: one-value
section: love
tab: one value
title: One value to rule them all.
---

```x2c
#include <assert.h>
#include <math.h>

int main(void) {
  // One eight-byte word holds a value and remembers what it is.
  Var count = 42, ratio = 2.5, name = "Ada";

  // Operators do the obvious thing for whatever is in there.
  Var next = count + 1, full = name + " Lovelace";

  // Every Var knows how to print itself.
  printf("%s %s %s\n", next, ratio, full);

  // Ask at runtime; the answer is the stored type, not a guess.
  assert(count is int && ratio is double && name is String);

  // Cross a typed boundary and the Var converts itself.
  int whole = count; double part = ratio;

  // Even printf's %d and %f know what to do with one.
  printf("%d %f %f\n", count, ratio, sin(ratio));
  return 0;
}
```

`Var` is the value type the rest of x2c is built on. It is an eight-byte
tagged word: a number, a `String`, a pointer, a `Symbol`, plus a tag that
says which. Every collection stores Vars, every `%s` prints one, and every
typed C boundary converts one.

You get a dynamic language's ergonomics inside a C program, and the static
types are still there. The compiler checks static types; a Var's tag is
checked at run time.
