---
slug: runtime-lisp
section: magic
home: true
order: 6
tab: runtime Lisp
title: Keep a rule editable at runtime.
---

```x2c
~#include <assert.h>
~int main(void) {
// Expose an ordinary typed function to the runtime interpreter.
auto Lisp lisp = Lisp.new();
$lisp.bind(lisp, "seats-left", seats_left);

// Keep the party together, or admit as many people as fit.
List together = %(lambda (plan n)
  (if (<= n (seats-left plan)) n 0));
List split = %(lambda (plan n)
  (if (<= n (seats-left plan)) n (seats-left plan)));

// Supply either policy as data to the same evaluator.
int whole = lisp.eval($(together, "free", 12));
int partial = lisp.eval($(split, "free", 12));
printf("together: %d; split: %d\n", whole, partial);
~assert(whole == 0 && partial == 2);
~return 0;
~}

int seats_left(String plan) => plan == "pro" ? 25 : 2;
```

Evaluate a Lisp expression using a native binding supplied by the host program. The surrounding program stays compiled while the policy remains data that can be changed and evaluated.
