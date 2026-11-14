---
slug: scopes
section: love
home: true
order: 8
tab: memory
title: Let byte-gones be bygones.
---

```x2c
auto int item_count(void) { // Reclaim on return.
  return ["red", "green", "blue"].len();
}

~int main(void) {
  auto Array owned = [1, 2]; // Clean up the value held on exit.
  Map counts = auto {files: 2}; // Clean up the acquired value.
~  printf("items: %zu, files: %d\n",
~         owned.length, (int) counts[<files>]);

  auto { // Reclaim this region's allocations together.
    Array temporary = [1, 2, 3];
~    printf("region: %zu\n", temporary.length);
  }

  auto for (int i = 0; i < 2; i++) // One region.
    Array.new().push(i);
  for (int i = 0; i < 2; i++) auto { // Per iteration.
    Array.new().push(i);
  }

  auto Scope work = NULL; // Destroy this Scope at block exit.
  Array items;
  auto (&work) items = [1, 2, 3]; // Select a destination.
  printf("destination: %zu\n", items.length); // Still alive.
~  printf("function: %d\n", item_count());
~  return 0;
~}
```

Declaration `auto` cleans up the current value; initializer `auto` cleans up the acquired value. Inferred `auto name = value` and `$auto(value)` provide the same respective cleanups. Raw pointers need a cleanup operation.

Region `auto` reclaims allocations on every exit. It wraps blocks, statements, or functions. `auto (&work)` only selects and restores a destination; the managed `Scope` supplies reclamation.
