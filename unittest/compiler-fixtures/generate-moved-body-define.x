/* A function body written under conditional arms moves after the file's
   declarations, and C decides the groups reopened around it where it
   lands. It therefore lands before a later `#define` or `#include` that
   could choose another arm, and before a group containing one. */

#ifdef FAST
static int mode(void) { return 1; }
#else
static int mode(void) { return 2; }
#endif

#define FAST 1

#ifndef LATE
static int late(void) { return 3; }
#endif

#ifdef __STDC__
#define LATE 1
#endif

#ifdef __STDC__
#ifndef NESTED
static int nested(void) { return 4; }
#endif
#define NESTED 1
#endif

#ifndef bitand
static int before_include(void) { return 5; }
#endif

#include <iso646.h>

int main(void) {
  printf("mode %d %d %d %d\n", mode(), late(), nested(), before_include());
  return 0;
}
