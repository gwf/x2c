---
slug: runtime-lisp
section: magic
tab: lisp
title: Rules are data. Let the program read them.
---

```x2c
~#include <assert.h>
~
int main(void) {
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
  return 0;
}

int seats_left(String plan) => plan == "pro" ? 25 : 2;
```

`Lisp.new` embeds an interpreter; `$lisp.bind` hands it a native function.
Two policies arrive as Lists, run through the same evaluator, and come back
as `int`, because assignment converts the result.

This is the Lisp heritage x2c kept at run time: a scripting layer that
costs one object and no second build system. Your users can edit the rules
without recompiling your program.
