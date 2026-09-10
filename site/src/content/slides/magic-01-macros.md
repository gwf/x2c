---
slug: macros
section: magic
tab: macros
---

```x2c
~#include <assert.h>
macro Statement $swap(Expr $left, Expr $right)
  using $temporary => {
    $(x2c.syntax.type $left) $temporary = $left;
    $left = $right;
    $right = $temporary;
}

~int main(void) {
// The same macro works with different types.
int left = 20, right = 22;
$swap(left, right);

String first = %"hello", last = %"world";
$swap(first, last);
printf("%d %d; %s %s\n", left, right, first, last);
~assert(left == 22 && right == 20);
~assert(first == %"world" && last == %"hello");
~return 0;
~}
```

`$swap` receives parsed expressions, and `x2c.syntax.type` supplies
the temporary's type. `using` gives it a name that cannot collide with
caller names. The same three generated statements swap integers or
strings, without a separate macro for each type.
