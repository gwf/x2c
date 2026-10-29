---
title: Arrays
group: Values
---

```x2c
~#include <assert.h>
~int main(void) {
Array a = [3, 1, 2];                       // mutable, with identity
a.push(4); a[0] = 9;                        // index, update, grow
assert(a.len() == 4 && a[-1] == 4 && a[1:3] == [1, 2]);
Array b = a, c = a.copy();                  // b IS a; c is a shallow copy
b.sort();
assert(a === b && a == [1, 2, 4, 9] && c == [9, 1, 2, 4]);
foreach (int x in a) printf("%d ", x);
Array m = a.map(%!(x) => x * 2);            // map, filter, foldl, sort_with
a.pop();
assert(m[3] == 18 && 2 in a && a.len() == 3);
~return 0;
~}
```

- `==` compares contents, `===` compares identity. Copies and slices are
  shallow.
- `[]` is a fresh empty Array. Negative indexes count from the end.
- `ArrayInt`, `ArrayDbl`, `ArrayString` from `typed-array.x` store
  unboxed elements and index like C.
