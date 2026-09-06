/*  exception-hot-paths.x -- focused Error transfer timings */


#include <stdint.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}


static void result(const char *name, uint64_t elapsed, int count) {
  printf("%s,%.3f\n", name, (double) elapsed / count);
}


int main(void) {
  int normal_count = 5000000, raise_count = 1000000;
  unsigned long sink = 0;
  uint64_t start;

  Error.initialize();
  try {
    sink++;
  }
  catch: return 1;
  try {
    raise %(invariant (value 1));
  }
  catch %(invariant (value ?value)): {
    sink += value.integer();
  }

  start = now_ns();
  for (int i = 0; i < normal_count; i++) {
    try {
      sink += i & 1;
    }
    catch: return 1;
  }
  result("try-normal", now_ns() - start, normal_count);

  start = now_ns();
  for (int i = 0; i < raise_count; i++) {
    try {
      raise %(invariant (value 1));
    }
    catch %(invariant (value ?value)): {
      sink += value.integer();
    }
  }
  result("raise-catch", now_ns() - start, raise_count);

  if (sink == 0) return 1;
  return 0;
}
