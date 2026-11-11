---
slug: keywords
section: magic
home: true
order: 3
tab: keywords
title: Give a convention its own syntax.
---

```x2c
~#include <assert.h>
macro Decorator $control.with_lock(Stmt $body, Expr $lock) { {
    Mutex held = $lock;
    held.lock();
    defer held.unlock();
    $body
  } }

keyword with_lock $control.with_lock;

~int main(void) {
auto Mutex mutex = Mutex.new();
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

Turn locking and cleanup into a statement. The decorator introduces the held lock and its deferred release, so the body can concentrate on the operation being protected.
