---
slug: speed
section: power
tab: speed
title: Reads like Python, runs close to C.
links:
  - label: The measured benchmark run
    href: https://github.com/gwf/x2c/blob/f5031f767e3905e650af9ae2d9733182e45c1d3f/examples/shootout/results/current.md
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

In the 1 November 2026 Benchmarks Game run, idiomatic x2c ran the eight
shared problems at a median of 2.52 times C's time, and x2c tuned with these typed collections
at 1.07. Python took 20 times, Go 1.74, Rust 1.08. The x2c came in at 1.16
times Python's line count. Those are local measurements of those programs on
one machine, not a ranking of the universe.
