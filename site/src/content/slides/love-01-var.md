---
slug: var
section: love
home: true
order: 0
tab: one value
title: One value, many kinds.
---

```x2c
~#include <assert.h>
~#include <math.h>

~int main(void) {
  // Var holds different kinds of values.
  Var count = 42, ratio = 2.5, name = "Ada";

  // Ordinary operators work on Vars.
  Var next = count + 1, full = name + " Lovelace";

  // Vars format themselves with %s.
  printf("%s %s %s\n", next, ratio, full);

~  // Test Var properties at runtime.
~  assert(count is int && ratio is double && name is String);

  // Types are checked statically and dynamically as needed.
  int whole = count; double part = ratio;

  // %d and %f also convert Vars.
  printf("%d %f %f\n", count, ratio, sin(ratio));
~  return 0;
~}
```

A Var holds a number, text, or a collection. Operators and methods let you work with the value it holds, while ordinary C types remain available when you want them.
