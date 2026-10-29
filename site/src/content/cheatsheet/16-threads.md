---
title: Threads, channels, and locks
group: Concurrency
---

```x2c
#include <assert.h>

static Var worker(const void *input, size_t bytes) => *(const int *) input;

int main(void) {
  Channel ch = auto Channel.new(<i32>, 2);         // typed, bounded
  int total = 0;
  Thread.run([                                      // start all, join all
    %!(void) => { for (int i = 1; i <= 4; i++) ch.send(i); ch.close(); },
    %!(void) using &total => { foreach (int v in ch) total += v; }
  ]);
  assert(total == 10);
  Mutex m = auto Mutex.new();
  $lock(m) { total++; }                             // held for one block
  Thread t = Thread.start_raw(worker, &total, sizeof total);
  Var result = t.join(); t.free();                  // join returns a Var
  assert(result == 11);
  return 0;
}
```

- `Thread.start_raw` copies its input bytes; `Thread.start` passes a Var.
- A Channel of `<var>` carries anything; `Channel.new()` is a rendezvous.
  Receiving from a closed, drained channel yields `void`.
- `threaded int counter;` is thread-local storage.
