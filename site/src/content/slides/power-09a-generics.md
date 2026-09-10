---
slug: generics
section: power
tab: generics
---

```x2c
~#include <assert.h>
// Opt into the ready-made typed collection families.
#include "typed-array.x"
#include "typed-map.x"
#include "typed-list.x"

~int main(void) {
// Store native ints and count each response code.
ArrayInt responses = %[200, 200, 404, 200, 500, 404];
MapIntInt counts = %{};
for (int i = 0, n = responses.len(); i < n; i++)
  counts[responses[i]] += 1;

// A typed List fixes the report order, including absent codes.
ListInt codes = %(200 403 404 500);
for (ListInt rest = codes; rest; rest = rest.cdr()) {
  int code = rest.car();
  printf("%d: %d\n", code, counts.getdefault(code, 0));
}
~assert(counts.get(200) == 3 && counts.get(404) == 2);
~assert(counts.get(500) == 1 && counts.getdefault(403, 0) == 0);
~assert(counts.len() == 3 && responses.len() == 6);
~assert(codes.car() == 200 && codes.last() == 500);
~return 0;
~}
```

`ArrayInt` and `MapIntInt` access and update native values without
boxing through `Var`. Array indexing and arithmetic updates become direct
C operations; typed map methods expose concrete types to the C optimizer.
`ListInt` supplies typed methods over shared `List` cells. Familiar literals
construct all three.
