---
slug: runtime-lisp
section: magic
tab: runtime
---

```x2c
~#include <assert.h>
int seats_left(String plan) => plan == %"pro" ? 25 : 2;

~int main(void) {
// Expose an ordinary typed function to the runtime interpreter.
Lisp lisp = Lisp.new();
defer lisp.destroy();
$lisp.bind(lisp, "seats-left", seats_left);

// Keep the party together, or admit as many people as fit.
List together = %(lambda (plan n)
  (if (<= n (seats-left plan)) n 0));
List split = %(lambda (plan n)
  (if (<= n (seats-left plan)) n (seats-left plan)));

// Supply either policy as data to the same evaluator.
int whole = lisp.eval(%($together "free" 12));
int partial = lisp.eval(%($split "free" 12));
printf("together: %d; split: %d\n", whole, partial);
~assert(whole == 0 && partial == 2);
~return 0;
~}
```

`$lisp.bind` exposes the native `seats_left` function to `Lisp.eval`.
Two `List` policies call that binding: one rejects an oversized party,
the other admits those who fit. Rules travel as data, and assigning
the evaluator's results converts them to `int`.
