---
slug: keywords
section: magic
tab: keywords
title: Make a statement. Literally.
---

```x2c
~#include <assert.h>
~
macro Decorator $control.with_lock(Stmt $body, Expr $lock) { {
    Mutex held = $lock;
    held.lock();
    defer held.unlock();
    $body
  } }

keyword with_lock $control.with_lock;

int main(void) {
  Mutex mutex = Mutex.new();
  defer mutex.free();
  try with_lock(mutex) { raise %(oops); }
  catch %(oops): {
    ~assert(mutex.try_lock());
    ~mutex.unlock();
    puts("caught, and the lock is already free");
  }
  return 0;
}
```

A decorator that takes a block can be given a name with `keyword`, and
now `with_lock(m) { ... }` is part of the language in this file. The lock
is evaluated once and released on every exit, including an exception.

`foreach`, `class`, and `auto` are implemented this way too. The compiler's
own keywords are made the same way as yours.
