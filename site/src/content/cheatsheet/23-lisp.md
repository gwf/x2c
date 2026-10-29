---
title: Runtime Lisp
group: Compile time
---

```x2c
#include <assert.h>

int seats(String plan) => plan == "pro" ? 25 : 2;

int main(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  $lisp.bind(lisp, "seats", seats);                  // expose a native function
  List rule = %(lambda (plan n) (if (<= n (seats plan)) n 0));
  int admitted = lisp.eval($(rule, "pro", 12));      // code is a List
  Var sum = lisp.eval_string("(+ 1 2)");
  assert(admitted == 12 && sum == 3);
  return 0;
}
```

- The interpreter is the runtime's: one object, no second build. Rules,
  configuration, and user scripts can be data your program evaluates.
- `.xlisp` files load with `lisp.load`; the REPL and `examples/programs`
  show larger uses.
