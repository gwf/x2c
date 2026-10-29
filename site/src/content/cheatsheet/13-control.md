---
title: Control flow, matching, and binding
group: Flow
---

```x2c
~#include <assert.h>
~int main(void) {
Array rows = [%(pair 2 3), %(one 7)];
foreach (List row in rows)                          // anything with elements
  if (row ~= %(pair ?(int a) ?(int b)) && a < b)    // test and bind at once
    printf("%d < %d\n", a, b);
match (rows[1]) {                                   // first case by shape
  case %(pair ?a ?b): puts("two");
  case %(one ?x): printf("one %s\n", x);
  default: puts("?");
}
(int a, int b) = %(1 2);                            // destructure
int n = 1;
with (n = 5) { assert(n == 5); }                    // assign, then restore
alias total to a + b;                               // name an expression
assert(n == 1 && total == 3 && 2 in %(1 2 3));
~return 0;
~}
```

- Patterns: `?x` binds one value, `?(int x)` with a type, `*rest` binds
  the remainder, `?` ignores one. A `case` may add `if (guard)`.
- `foreach ((k, v) in map)` unpacks pairs; `foreach (x in file)` reads
  lines.
- `a[start:stop:step]` slices Strings, Lists, and Arrays. `x in c` tests
  membership; `v is T` tests a Var's type.
