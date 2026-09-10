---
slug: symbols
section: love
tab: symbols
---

```x2c
#include <assert.h>

~int main(void) {
// Names are values, without declaring enum constants.
Symbol running = <running>, state = <queued>;

// Symbol literals are constants, so ordinary C switch works.
switch (state) {
  case <queued>:  puts(%"$state: waiting for a worker"); break;
  case <running>: puts(%"$state: doing the work"); break;
  default:        puts(%"$state: no work left");
}

// An ordered vocabulary, built entirely at compile time.
SymbolSet stages = %<<queued running done>>;
assert(stages.contains(state) && !stages.contains(<failed>));
state = stages[stages.index(state) + 1];
assert(state == running);

// Iterate in declared order and recover each name's text.
foreach (Symbol stage, stages)
  printf("%d: %s\n", stages.index(stage), stage.str());
~return 0;
~}
```

`Symbol` gives names constant-time equality without allocating or
occupying C's identifier namespace. `SymbolSet` adds declaration order,
indexing, and membership with no runtime setup. `SymbolSet.index` locates
a stage; `Symbol.str` recovers its text. Compact names have a fixed
capacity; `Atom` handles arbitrary external names.
