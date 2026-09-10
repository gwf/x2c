/*  handles.c -- native handle counters for the diagnostic build.

    The counters are relaxed atomics: the hooks sit on the wrapper
    creation path, so they must cost close to nothing, and a benchmark
    reads them between steps rather than during one. The peak is kept with
    a compare-and-swap loop, which only runs while the peak is rising.

    A build without XT_HANDLE_COUNTERS never calls the hooks, so every
    reader returns 0 and `xb_handles_enabled` says why.
*/
#include "handles.h"

#include <stdatomic.h>

static _Atomic uint64_t created[XT_HANDLE_KINDS];
static _Atomic uint64_t destroyed[XT_HANDLE_KINDS];
static _Atomic uint64_t peak[XT_HANDLE_KINDS];

static int in_range(int kind) { return kind >= 0 && kind < XT_HANDLE_KINDS; }

void xt_handle_created(int kind) {
  if (!in_range(kind)) return;
  uint64_t made = atomic_fetch_add_explicit(&created[kind], 1,
                                            memory_order_relaxed) + 1;
  uint64_t gone = atomic_load_explicit(&destroyed[kind],
                                       memory_order_relaxed);
  uint64_t live = made > gone ? made - gone : 0;
  uint64_t high = atomic_load_explicit(&peak[kind], memory_order_relaxed);
  while (live > high &&
         !atomic_compare_exchange_weak_explicit(&peak[kind], &high, live,
                                                memory_order_relaxed,
                                                memory_order_relaxed))
    ;
}

void xt_handle_destroyed(int kind) {
  if (!in_range(kind)) return;
  atomic_fetch_add_explicit(&destroyed[kind], 1, memory_order_relaxed);
}

int xb_handles_enabled(void) {
#ifdef XT_HANDLE_COUNTERS
  return 1;
#else
  return 0;
#endif
}

uint64_t xb_handles_created(int kind) {
  return in_range(kind)
    ? atomic_load_explicit(&created[kind], memory_order_relaxed) : 0;
}

uint64_t xb_handles_destroyed(int kind) {
  return in_range(kind)
    ? atomic_load_explicit(&destroyed[kind], memory_order_relaxed) : 0;
}

uint64_t xb_handles_live(int kind) {
  if (!in_range(kind)) return 0;
  uint64_t made = atomic_load_explicit(&created[kind], memory_order_relaxed);
  uint64_t gone = atomic_load_explicit(&destroyed[kind],
                                       memory_order_relaxed);
  return made > gone ? made - gone : 0;
}

uint64_t xb_handles_peak(int kind) {
  return in_range(kind)
    ? atomic_load_explicit(&peak[kind], memory_order_relaxed) : 0;
}
