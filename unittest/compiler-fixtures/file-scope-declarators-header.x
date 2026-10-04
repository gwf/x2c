#include "x2c.x"

// A public declaration with several initialized declarators puts only
// their `extern` declaration in the header; the initializers, including
// one that runs at startup, stay in the source.
int bump(void);
int c1 = 2, c2 = c1 * 10 + bump();
int calls = 0;
int bump(void) { return ++calls; }

int main(void) {
  printf("calls=%d c1=%d c2=%d\n", calls, c1, c2);
  return 0;
}
