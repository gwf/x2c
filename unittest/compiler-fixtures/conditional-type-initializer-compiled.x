/*  A unit whose type initializer is defined in two arms of conditional
    groups, one nested, and compiled from the nested one. It runs once, at
    the first entry, after the file-scope initialization it reads. A type
    shutdown in a false arm is not registered. */

#include "x2c.x"

#define FEATURE 0

typedef struct Probe *Probe;

static List names = %(alpha beta gamma);
static int body_runs = 0, seen = 0;

#if FEATURE
void Probe.initialize(void) { body_runs += 100; }
#else
#  ifndef MISSING
void Probe.initialize(void) {
  body_runs++;
  seen = names.len();
}
#  endif
#endif

#ifdef MISSING
void Probe.shutdown(void) { body_runs += 100; }
#endif

int count(void) { return names.len(); }

int main(void) {
  printf("%d %d %d\n", count(), body_runs, seen);
  return count() == 3 && body_runs == 1 && seen == 3 ? 0 : 1;
}
