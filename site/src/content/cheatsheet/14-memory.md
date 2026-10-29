---
title: Memory by lifetime
group: Memory and errors
---

```x2c
#include <assert.h>

Array survey(void) => ["a.dat", "b.dat"];

int main(void) {
  for (int day = 0; day < 2; day++) auto {    // one region per iteration
    Array files = survey();                   // freed when the iteration ends
    foreach (String f in files) auto {        // a nested region per file
      Map findings = {size: f.len()};
      assert(findings[<size>] == 5);
    }
  }
  Scope.retain();                             // the same thing by hand
  defer Scope.release();                      // defer runs on every exit
  File tmp = auto tmpfile();                  // auto: clean up at block exit
  tmp.puts("x");
  int *raw = xmalloc(sizeof *raw);            // Scope-owned C allocation
  *raw = 1;
  assert(*raw == 1);
  return 0;
}
```

- No garbage collector, no reference counts, no `free`. Arrays, Maps, and
  class objects live in the current Scope; Strings, Lists, and Symbols
  live in pools with nested lifetimes.
- The translator warns when a value can outlive its region.
- `Context` isolates runtime state per thread; `xfree` releases early.
