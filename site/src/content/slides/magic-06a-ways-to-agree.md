---
slug: ways-to-agree
section: magic
tab: same list
---

```x2c
~#include <assert.h>

~int main(void) {
List comptime = $squares(3);

// A literal compiles to a form similar to the cons cells below.
List literal = %(1 4 9);

// Explicit construction reveals the underlying C functions.
List constructed = cons(int_var(1),
  cons(int_var(4), cons(int_var(9), NULL)));

// Runtime Lisp will build it on the fly.
auto Lisp lisp = Lisp.new();
List runtime = lisp.eval(%(list (* 1 1) (* 2 2) (* 3 3)));

~List ways = $(comptime, literal, constructed, runtime);
~foreach (List left in ways)
~  foreach (List right in ways) assert(left == right);
assert(comptime == literal && literal == constructed &&
       constructed == runtime);
puts("All four lists are equal.");
~return 0;
~}

// A meta function computes the List during translation.
meta static List squares(int n) {
  Array items = [];
  for (int i = 1; i <= n; i++) items.push(i * i);
  return items.list_free();
}
```

A `meta` function computes the squares during translation, and a literal and
direct `cons` calls write `(1 4 9)` out. Runtime Lisp calculates the squares
on the fly to produce the same List.
All four results compare equal in constant time because they resolve to the
exact same object.
