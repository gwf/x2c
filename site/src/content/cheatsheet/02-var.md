---
title: Var, the one value
group: Values
---

```x2c
~#include <assert.h>
~int main(void) {
Var v = 42, s = "text", p = %(1 2);       // one 8-byte tagged word
assert(v is int && s is String && p is List);
int n = v;                                 // a typed destination converts
Var sum = v + 1, both = s + "!";           // operators follow the contents
printf("%s %s %d\n", sum, both, n);        // %s prints any Var
assert(v in %(41 42 43) && s is not List); // membership, negated test
Var missing = void, empty = [];            // absence is void; [] is false
assert(missing is void && !empty);
~return 0;
~}
```

- Every collection stores Vars; every typed boundary (assignment,
  argument, return) converts one.
- `void` is absence: a missing Map key, a function that returned nothing.
  Test it with `is void`; asking it for truth is an error. An empty Array
  or String is false. `NULL`, `""`, and `nil` are three other values.
- `v.integer()`, `v.str()`, `v.repr()`, `(long) v` convert explicitly.
