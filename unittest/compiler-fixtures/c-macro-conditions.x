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

// The C compile makes `char` signed. A multi-character constant, a shift
// by 64 or more, and a quotient that does not fit stay undecided, so
// both arms parse and the C compiler chooses.
#if '\xff' < 0 && '\0' == 0
int signed_char(void) => 1;
#else
int signed_char(void) => 2;
#endif

#if 'ab' == 'a'
int two_chars(void) => 1;
#else
int two_chars(void) => 2;
#endif

#if (1 << 64) == 1
int wide_shift(void) => 1;
#else
int wide_shift(void) => 2;
#endif

#if (-9223372036854775807 - 1) / -1 < 0
int quotient(void) => 1;
#else
int quotient(void) => 2;
#endif

#if (-9223372036854775807 - 1) % -1 == 0
int modulus(void) => 1;
#else
int modulus(void) => 2;
#endif

int main(void) {
  printf("%d %d\n", level(), one());
  printf("%d %d %d %d %d\n", signed_char(), two_chars(), wide_shift(),
         quotient(), modulus());
  return 0;
}
