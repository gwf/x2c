/*  A unit whose type initializer is compiled out, from a false arm and
    from a nested group. The unit's file-scope initialization still runs at
    its entries and registers the type shutdown compiled from a true arm. */

#include "x2c.x"

#define FEATURE 0
#define NESTED 1

typedef struct Probe *Probe;

static List names = %(alpha beta gamma);
static int body_runs = 0;

#if FEATURE
void Probe.initialize(void) { body_runs++; }
#elif NESTED
#  ifdef MISSING
void Probe.initialize(void) { body_runs++; }
#  endif
#endif

#if NESTED
void Probe.shutdown(void) { printf("shutdown\n"); }
#endif

int count(void) { return names.len(); }

int main(void) {
  printf("%d %d\n", count(), body_runs);
  return count() == 3 && !body_runs ? 0 : 1;
}
