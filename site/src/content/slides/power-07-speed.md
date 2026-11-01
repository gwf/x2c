---
slug: speed
section: power
tab: speed
title: Reads like Python, runs like C.
links:
  - label: The shootout
    href: https://github.com/gwf/x2c/blob/main/examples/shootout-unofficial/README.md
---

```x2c
~#include <assert.h>
// Opt into the ready-made typed collection families.
#include "typed-array.x"
#include "typed-map.x"
#include "typed-list.x"

int main(void) {
  // Store native ints and count each response code.
  ArrayInt responses = [200, 200, 404, 200, 500, 404];
  MapIntInt counts = {};
  for (int i = 0, n = responses.len(); i < n; i++)
    counts[responses[i]] += 1;

  // A typed List fixes the report order, including absent codes.
  ListInt codes = %(200 403 404 500);
  for (ListInt rest = codes; rest; rest = rest.cdr()) {
    int code = rest.car();
    printf("%d: %d\n", code, counts.getdefault(code, 0));
  }
  ~assert(counts[200] == 3 && counts[404] == 2);
  ~assert(counts[500] == 1 && counts.getdefault(403, 0) == 0);
  ~assert(counts.len() == 3 && responses.len() == 6);
  ~assert(codes.car() == 200 && codes.last() == 500);
  return 0;
}
```

Typed collections such as `ArrayInt` and `MapIntInt` skip boxing entirely;
`responses[i]` becomes the load C would have emitted. Everything compiles
to C and goes through your C compiler's optimizer like anything else.

In the shootout, fourteen problems written in x2c ran at a median of 1.04
times C's time, where Python took 39 times C's, in about 1.5 times Python's
line count. Those are measurements of those programs on that machine, not a
ranking of the universe.
