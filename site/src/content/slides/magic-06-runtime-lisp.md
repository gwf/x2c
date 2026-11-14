---
slug: runtime-lisp
section: magic
home: true
order: 0
tab: runtime Lisp
title: Lisp and learn.
---

```x2c
~#include <assert.h>
~#include <lisp-bindings.x>

int seats_left(String plan) => plan == "pro" ? 25 : 2;

~int main(void) {
  // Expose an ordinary typed function to the runtime interpreter.
  auto Lisp lisp = Lisp.new();
  lisp.bind("seats-left", seats_left);

  // Keep the party together, or admit as many people as fit.
  List together = %(lambda (plan n)
    (if (<= n (seats-left plan)) n 0));
  List split = %(lambda (plan n)
    (if (<= n (seats-left plan)) n (seats-left plan)));

  // Supply either policy as data to the same evaluator.
  Var plan = "free", guests = 12;
  int whole = lisp.eval(%($together $plan $guests));
  int partial = lisp.eval(%($split $plan $guests));
  printf("together: %d; split: %d\n", whole, partial);
~  assert(whole == 0 && partial == 2);
~  return 0;
~}
```

Lisp uses the same Vars, Strings, Lists, and other values as compiled x2c. No separate data model or conversion layer stands between them. Bind a typed native function, then pass ordinary values through an editable Lisp policy. Here, each policy is a List, and the evaluator calls `seats_left` in the compiled host program. Change the policy without changing the evaluator.
