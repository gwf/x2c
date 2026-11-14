---
slug: keywords
section: magic
home: true
order: 4
tab: keywords
title: Lock of the draw.
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
~  {
~    assert(mutex.try_lock());
~    mutex.unlock();
    puts("caught, and the lock is already free");
~  }
~  return 0;
~}
```

Turn locking and cleanup into a statement. The decorator introduces the held lock and its deferred release, so the body can concentrate on the operation being protected.

`keyword` gives a macro an ordinary word spelling. This is, in fact, how some of the built-ins of the language are implemented. The compiler prelude defines `class` and `foreach` through keyword aliases backed by compiler helpers. Your program can use the same mechanism.
