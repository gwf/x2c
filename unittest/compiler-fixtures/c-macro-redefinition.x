#include <stdio.h>

#define SCALE 1
static int first(void) { return SCALE; }
#undef SCALE
#define SCALE 2
static int second(void) { return SCALE; }
#undef SCALE

#define LIMIT 3
static int limit(void) { return LIMIT; }
#undef LIMIT
#define LIMITED 4

#define STEP 5
static int step(void) { return STEP; }
#ifdef NEVER_DEFINED
#else
#ifdef NEVER_DEFINED
#else
static int inner(void) { return STEP; }
#endif
#undef STEP
#define STEP 6
#endif
static int next(void) { return STEP; }

int main(void) {
  printf("%d %d %d %d %d %d\n",
    first(), second(), limit(), step(), inner(), next());
  return 0;
}
