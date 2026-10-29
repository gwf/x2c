---
title: Lists
group: Values
---

```x2c
~#include <assert.h>
~int main(void) {
List xs = %(1 2 3), ys = cons(0, xs);      // immutable, shared, canonical
assert(ys.cdr() == xs && ys.car() == 0 && xs == %(1 2 3));
List sq = xs.map(%!(x) => x * x).filter(%!(x) => x > 1);
Var total = sq.foldl(0, %!(a, b) => a + b);
assert(sq == %(4 9) && total == 13 && xs.len() == 3);
int n = 5;
List built = %(start $n @xs end);          // $ inserts one, @ splices
assert(built == %(start 5 1 2 3 end) && $(n, n + 1) == %(5 6));
(int first, int second) = xs;              // destructure the first two
assert(first == 1 && second == 2 && xs.last() == 3);
~return 0;
~}
```

- Equal Lists are the same pointer: structural equality in constant time.
- `nil` and `NULL` are the empty List. `cons` is constant time and shares
  the tail.
- `car`, `cdr`, `cadr`, `assoc`, `reverse`, `sort`, `repr`, `str`,
  `list_free` on an Array.
