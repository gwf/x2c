---
title: Symbols and symbol sets
group: Values
---

```x2c
~#include <assert.h>
~int main(void) {
Symbol state = <queued>;                   // a 64-bit constant, no enum
switch (state) { case <queued>: puts("waiting"); break; default: break; }
SymbolSet stages = %<<queued running done>>;   // ordered, built at compile time
assert(stages.index(<running>) == 1 && stages.contains(state));
assert(state.str() == "queued" && stages[2] == <done>);
Map m = {queued: 1};                       // bare Map keys are Symbols
assert(m[<queued>] == 1 && m["queued"] is void);
~return 0;
~}
```

- Compact names fit a Symbol; `Atom` holds names of any length.
- `<name>` is the same value in a literal, a pattern, a `case`, and a
  Map key.
- Symbols cost nothing in C's identifier namespace, so `<error>` and
  `<free>` are fine.
