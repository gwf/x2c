#include "x2c.h"

// A C string literal cast to `String` is the String the assignment form
// promotes, so indexing past its end gives -1 as documented.
int main(void) {
  String s = "abc";
  printf("%d %d\n", s[10], ((String) "abc")[10]);
  printf("%c %d\n", ((String) "xyz")[1], ((String) "xyz").len());
  return 0;
}
