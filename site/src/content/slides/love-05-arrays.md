---
slug: arrays
section: love
tab: arrays
---

```x2c
#include <assert.h>

~int main(void) {
// Grow and update a sequence in place.
Array scores = %[7, 3, 9];
scores.push(5); scores[1] += 1;

// Sorting mutates; copy first to keep the original order.
Array ranked = scores.copy().sort().reverse();
assert(scores == %[7, 4, 9, 5] && scores !== ranked);

// Slices and map create new Arrays.
Array top = ranked[:2];
Array boosted = top.map(%!(score) => score + 1);
Var total = boosted.reduce(%!(a, b) => a + b);
printf("scores: %s; ranked: %s\n", scores.repr(), ranked.repr());

// Use indexed access or iterate over the resulting values.
foreach (Var score, boosted)
  printf("%s ", score);
printf("=> total %s, best %s\n", total, boosted[0]);
~return 0;
~}
```

`Array` combines indexed access, growth, slicing, and functional
operations. `Array.copy` creates a separate sequence; `Array.sort` and
`Array.reverse` mutate it. Assignment shares the object, `==` compares
contents, and `===` compares identity. Copies and slices are shallow:
nested objects remain shared.
