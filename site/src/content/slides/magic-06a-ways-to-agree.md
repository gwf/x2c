---
section: magic
tab: agreement
---

```x2c
~#include <assert.h>
~int main(void) {
// Compile-time Lisp can return an actual AST node.
List comptime = $(let ((cons-expr (lambda (n tail)
  `(expr ("List") (cons ,(x2c.literal.int n) ,tail)))))
  (cons-expr 1 (cons-expr 4 (cons-expr 9 '(nil)))));

// A literal compiles to a form similar to the cons cells below.
List literal = %(1 4 9);

// Explicit construction reveals the underlying C functions.
List constructed = cons(int_var(1),
  cons(int_var(4), cons(int_var(9), NULL)));

// Runtime Lisp will build it on the fly.
Lisp lisp = Lisp.new(); defer lisp.destroy();
List runtime = lisp.eval(%(list (* 1 1) (* 2 2) (* 3 3)));

~List ways = %($comptime $literal $constructed $runtime);
~foreach (List left, ways)
~  foreach (List right, ways) assert(left == right);
assert(comptime == literal && literal == constructed &&
       constructed == runtime);
puts("All four lists are equal.");
~return 0;
~}
```

Compile-time Lisp, a literal, and direct `cons` calls build `(1 4 9)`.
Runtime Lisp calculates the squares to produce the same List.
All four results compare equal in constant time because they resolve to the
exact same object.
