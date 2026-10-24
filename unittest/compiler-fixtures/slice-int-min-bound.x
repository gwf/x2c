#include "x2c.x"
#include <limits.h>

// An explicit INT_MIN bound is an ordinary out-of-range bound, not an
// omitted one; INT_MIN + 1 is the control. An unsigned literal that
// converts to INT_MIN behaves as the same value held in a variable.
int main(void) {
  Array a = auto [10, 20, 30];
  String s = "abc";
  List l = %(1 2 3);
  int lo = INT_MIN, near = INT_MIN + 1;
  printf("%s %s %s %s\n", a[:lo].repr(), a[:near].repr(),
         a[lo::-1].repr(), a[:lo:-1].repr());
  String head = s[:lo], near_head = s[:near];
  printf("%s %s %s %s\n", head ? head : "none",
         near_head ? near_head : "none", ((Var) l[:lo]).repr(),
         ((Var) l[:near]).repr());
  unsigned wide = 0x80000000u;
  printf("%s %s\n", a[:0x80000000u].repr(), a[:wide].repr());
  return 0;
}
