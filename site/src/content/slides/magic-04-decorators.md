---
slug: decorators
section: magic
tab: decorators
title: A decorator rewrites the function after it.
---

```x2c
~#include <assert.h>
~
macro Decorator $trace(Function $function) {
  printf("enter %s\n", $Code.name($function));
  defer printf("leave %s\n", $Code.name($function));
  @Code.body($function)
}

int main(void) {
  // Prints "enter answer", then "leave answer".
  int result = answer();
  ~assert(result == 42);
  return 0;
}

$trace()
int answer(void) => 42;
```

`$trace()` receives a whole parsed function, wraps its body, and hands back
a function with the same signature. `defer` makes the exit line fire even
on an early `return`.

The signature is unchanged, so callers and the linker see the same
function.
