/*  catch-runtime.x -- the cost of raising and catching with four static arms

    Each round raises one of four causes and catches it with a `try` whose
    four filtered arms are static patterns, so the arm selected moves from
    first to last. Prints nanoseconds per raise and catch. */

#include "x2c.x"
#include <time.h>

static void thrower(int i) {
  switch (i & 3) {
    case 0: raise %(bad-arg (value 1));
    case 1: raise %(not-found (path "p"));
    case 2: raise %(io-fail (path "q") (errno 2));
    default: raise %(bad-state (operation "op"));
  }
}

static int once(int i) {
  try thrower(i);
  catch %(bad-arg (value ?v)): return v.int();
  catch %(not-found *detail): return detail.len();
  catch %(io-fail (path ?p) *): return 3;
  catch %(bad-state *): return 4;
  return 0;
}

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e9 + t.tv_nsec;
}

int main(void) {
  int rounds = 2000000, sum = 0;
  for (int i = 0; i < 10000; i++) sum += once(i);
  double start = now();
  for (int i = 0; i < rounds; i++) sum += once(i);
  double elapsed = now() - start;
  printf("%.1f ns per raise and catch (%d)\n", elapsed / rounds, sum);
  return 0;
}
