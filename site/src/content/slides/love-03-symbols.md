---
slug: symbols
section: love
home: true
order: 5
tab: names
title: Give a value a name.
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
  SymbolSet stages = %<queued running done>;
  assert(stages.contains(state) && !stages.contains(<failed>));
  state = stages[stages.index(state) + 1];
  assert(state == running);

  // Iterate in declared order and recover each name's text.
  foreach (Symbol stage in stages)
    printf("%d: %s\n", stages.index(stage), stage.str());
~  return 0;
~}
```

Symbols provide named values for states, keys, and choices. An ordered vocabulary also gives related names an order, so a program can describe its domain without relying on unexplained numbers.
