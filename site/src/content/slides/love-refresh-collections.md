---
slug: collections
aliases: [lists, arrays, maps]
section: love
home: true
order: 2
tab: collections
title: Different containers, familiar operations.
---

```x2c
~#include <assert.h>

~int main(void) {
  // Lists are immutable and share structure; cons is constant time.
  List prices = %(3 5 8), extended = cons(2, prices);
  List doubled = extended.map(%!(price) => price * 2);
  assert(extended.cdr() == prices && doubled == %(4 6 10 16));

  // Arrays grow and mutate in place; copy first to keep the original.
  Array scores = [7, 3, 9];
  scores.push(5);
  Array ranked = scores.copy().sort().reverse();
  assert(scores == [7, 3, 9, 5] && ranked[:2] == [9, 7]);

  // Maps grow on write and tell absence from a stored zero.
  Map stock = {tea: 12, sugar: 0};
  stock[<tea>] -= 2;
  stock[<cocoa>] = 4;
  Var sugar;
  assert(stock.try_get(<sugar>, sugar) && sugar == 0);
  assert(stock.getdefault(<milk>, -1) == -1 && !stock.contains(<milk>));
  printf("%s %s %s\n", doubled.repr(), ranked.repr(), stock[<tea>]);
~  return 0;
~}
```

Lists, Arrays, and Maps serve different purposes. Their shared operations let you transform a sequence, rank values, and look up a result without rebuilding those operations for each container.
