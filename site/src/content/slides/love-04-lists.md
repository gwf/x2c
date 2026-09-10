---
slug: lists
section: love
tab: lists
---

```x2c
#include <assert.h>

~int main(void) {
// Prepend in constant time, sharing the original tail.
List prices = %(3 5 8), extended = cons(2, prices);
assert(extended.cdr() == prices && extended == %(2 3 5 8));

// Compose transformations without changing either input.
List totals = extended.map(%!(price) => price * 2);
List selected = totals.filter(%!(total) => total >= 10);

// Unpack values, then fold them into a single result.
Var (first, second) = selected;
Var sum = selected.foldl(0, %!(a, b) => a + b);
printf("selected: %s + %s = %s\n", first, second, sum);

// A literal can combine names, computed values, and nested Lists.
puts(%(total $sum items $selected).repr());
puts(%"original: $prices; extended: $extended");

// car gets the first value; cdr gets the rest, spliced with @.
List parts = %((first ${selected.car()}) (rest @{selected.cdr()}));
puts(parts.repr());
~return 0;
~}
```

`cons` prepends a value while sharing the original `List` tail. Equal
Lists share canonical structure, making equality a pointer comparison.
`List.map`, `List.filter`, and `List.foldl` compose without changing their
inputs. Nested literals and destructuring keep the resulting data as
readable as the operations that produce it.
