---
slug: collections
aliases: [lists, arrays, maps]
section: love
home: true
order: 3
tab: collections
title: Array of sunshine.
---

```x2c
~#include <assert.h>

~int main(void) {
  // Immutable Lists share tails and mix value kinds.
  List order = %("tea" 3 2.5), labeled = cons(<order>, order);
~  assert(labeled.cdr() == order);

  // Arrays grow and change in place.
  Array basket = ["tea", 3, 2.5];
  basket[1] += 1;
  basket.push(<packed>);
~  assert(basket == ["tea", 4, 2.5, <packed>]);

  // Maps find values by key.
  Map details = {name: "tea", quantity: 3, price: 2.5};
  details[<quantity>] += 1;
~  assert(basket[1] == details[<quantity>]);
  printf("%s\n%s\n%s: %s\n",
         labeled.repr(), basket.repr(),
         details[<name>], details[<quantity>]);
~  return 0;
~}
```

C's native arrays do not grow, and keyed lookup needs a separate data structure. x2c supplies Lists, growable Arrays, and Maps with literals and common operations. Their Var elements can mix value kinds. Lists share immutable tails; Arrays grow and change in place; Maps find values by key.
