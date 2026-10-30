---
slug: macros
section: magic
tab: macros
title: Macros over syntax, not over text.
---

```x2c
~#include <assert.h>
~
macro Stmt $swap(Expr $left, Expr $right) {
  $Code.type($left) temporary = $left;
  $left = $right;
  $right = temporary;
}

int main(void) {
  // The same macro works with different types.
  int left = 20, right = 22;
  $swap(left, right);

  String first = "hello", last = "world";
  $swap(first, last);
  printf("%d %d; %s %s\n", left, right, first, last);
  ~assert(left == 22 && right == 20);
  ~assert(first == "world" && last == "hello");
  return 0;
}
```

`$swap` takes two parsed expressions, reads their type from the compiler,
and writes three statements. `temporary` is hygienic: it cannot collide
with any name at the call site.

One macro, every type, and not a single `do { } while (0)` in sight.
