---
slug: decorators
section: magic
home: true
order: 2
tab: decorators
title: Transform a function at its definition.
---

```x2c
~#include <assert.h>
macro Decorator $trace(Function $function) {
  printf("enter %s\n", $Code.name($function));
  defer printf("leave %s\n", $Code.name($function));
  @Code.body($function)
}

$trace()
int answer(void) => 42;

~int main(void) {
  // Prints "enter answer", then "leave answer".
  int result = answer();
~  assert(result == 42);
~  return 0;
~}
```

A decorator adds tracing around a function body. The function keeps its ordinary calling interface while the transformation supplies the repeated entry and exit work.
