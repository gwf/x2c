#include "x2c.x"
#include <limits.h>

// An explicit INT_MIN bound is an ordinary out-of-range bound, not an
// omitted one; INT_MIN + 1 is the control.
int main(void) {
  Array a = $auto([10, 20, 30]);
  String s = "abc";
  List l = %(1 2 3);
  int lo = INT_MIN, near = INT_MIN + 1;
  printf("%s %s %s %s\n", a[:lo].repr(), a[:near].repr(),
         a[lo::-1].repr(), a[:lo:-1].repr());
  printf("[%s] [%s] %s %s\n", s[:lo], s[:near],
         ((Var) l[:lo]).repr(), ((Var) l[:near]).repr());
  return 0;
}
