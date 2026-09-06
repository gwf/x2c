#include <assert.h>
macro Decorator $control.with_lock(Block $body, Expr $lock)
  using $held => { {
    Mutex $held = $lock;
    $held.lock();
    defer $held.unlock();
    $body
  } }

keyword with_lock $control.with_lock;

int main(void) {
Mutex mutex = Mutex.new();
defer mutex.free();
try with_lock(mutex) { raise %(oops); }
catch %(oops):
{
assert(mutex.try_lock());
mutex.unlock();
  puts("caught, and the lock is already free");
}
return 0;
}
