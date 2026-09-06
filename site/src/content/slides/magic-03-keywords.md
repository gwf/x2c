---
section: magic
tab: keywords
---

```x2c
~#include <assert.h>
macro Decorator $control.with_lock(Block $body, Expr $lock)
  using $held => { {
    Mutex $held = $lock;
    $held.lock();
    defer $held.unlock();
    $body
  } }

keyword with_lock $control.with_lock;

~int main(void) {
Mutex mutex = Mutex.new();
defer mutex.free();
try with_lock(mutex) { raise %(oops); }
catch %(oops):
~{
~assert(mutex.try_lock());
~mutex.unlock();
  puts("caught, and the lock is already free");
~}
~return 0;
~}
```

`$control.with_lock` evaluates the lock expression once and wraps a
`Block` with `Mutex.lock` and deferred `Mutex.unlock`. `keyword` gives
that decorator the spelling `with_lock`. The lock is released when the
block exits, including when an exception leaves it.
