/*  A unit with file-scope initialization whose first function definition
    sits in a false conditional arm. The initialization guard and the file
    initializer are declared outside every conditional group, so the
    generated C compiles whichever arms the C compiler selects. */

#include "x2c.x"

#define FAST 0

static List names = %(alpha beta gamma);

#if FAST
static int speed(void) { return 2; }
#else
#  ifdef MISSING
static int speed(void) { return 3; }
#  else
static int speed(void) { return 1; }
#  endif
#endif

int main(void) {
  printf("%d %d\n", speed(), names.len());
  return 0;
}
