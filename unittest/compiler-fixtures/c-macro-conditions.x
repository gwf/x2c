#include "x2c.x"

// A condition whose names are all visible, known never to be defined, or
// literals is decided, so only its taken arm parses. The directives stay
// in the generated C, where the C compiler decides them the same way.
#define LEVEL 2

#if LEVEL > 1 && defined(LEVEL)
int level(void) { return 1; }
#elif not x2c (
#else
not x2c either
#endif

#if 1
int one(void) => 1;
#else
int one(void) { unfinished
#endif

#ifdef _MSC_VER
only for MSVC
#endif

#if !defined(LEVEL) || LEVEL * 2 != 4 || 'a' != 97
not taken
#endif

int main(void) {
  printf("%d %d\n", level(), one());
  return 0;
}
