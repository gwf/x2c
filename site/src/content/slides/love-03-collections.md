---
slug: collections
section: love
tab: collections
title: Three shapes, one set of brackets.
---

```x2c
#include <assert.h>

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
~return 0;
~}
```

`%(...)` is a List, `[...]` is an Array, `{...}` is a Map, and the
brackets mean the same thing on the way back out. Lists are the Lisp half
of the family tree: immutable, shared, happy to be mapped and filtered.
Arrays and Maps are the workhorses: push, sort, slice, index, update in
place.

Pick by lifetime and identity, not by what the standard library happened
to hand you.
