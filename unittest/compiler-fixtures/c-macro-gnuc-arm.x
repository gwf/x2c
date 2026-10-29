#include "x2c.x"

// x2c output is compiled by a GNU-style compiler, so `__GNUC__` is defined
// and only the first arm of this function header parses. Its value is
// unknown, so `#if __GNUC__ >= 4` stays undecided and both arms parse.
#ifdef __GNUC__
int main(void) {
#else
int main() {
#endif
#if __GNUC__ >= 4
  printf("gnu\n");
#else
  printf("other\n");
#endif
  return 0;
}
