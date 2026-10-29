---
slug: names
section: love
tab: names
title: A name should not cost an enum.
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
foreach (Symbol stage in stages)
  printf("%d: %s\n", stages.index(stage), stage.str());
~return 0;
~}
```

`<queued>` is a `Symbol`: a 64-bit word that compares in constant time,
prints its own spelling, and occupies nothing in C's identifier namespace.
A `SymbolSet` gives a vocabulary an order and an index, with no runtime
setup at all.

States, kinds, tags, Map keys: anything you were about to write an enum
for, and then a `switch` to print.
