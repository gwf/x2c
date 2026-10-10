---
slug: decorators
section: magic
tab: decorators
---

```x2c
~#include <assert.h>
macro Decorator $trace(Function $function) {
  printf("enter %s\n",
    $(x2c.literal.string (Code.name $function)));
  defer printf("leave %s\n",
    $(x2c.literal.string (Code.name $function)));
  @(Code.body $function)
}

$trace()
int answer(void) => 42;

~int main(void) {
// Prints "enter answer", then "leave answer".
int result = answer();
~assert(result == 42);
~return 0;
~}
```

`$trace` receives a parsed `Function` and wraps its body while
preserving its signature. `Code.name` supplies the trace label;
`defer` prints the exit trace even when the body returns. Callers still
use an ordinary function.
