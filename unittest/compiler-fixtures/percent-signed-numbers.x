#include "x2c.x"
#include <stdio.h>
#include <limits.h>

int main(void) {
  List small = %(-5 5 -0x1e -0b101 -0o7 -5U -5L -5LL);
  List minima = %(-2147483648 -9223372036854775808L -9223372036854775808LL);
  printf("%d %d %d %d %d\n", small[0] is <i32>, small[0] == -5,
         small[2] == -30, small[3] == -5, small[4] == -7);
  printf("%d %d %d %d %d %d\n", small[5] is <u32>,
         small[5] == (unsigned) -5, small[6] is <long>, small[6] == -5L,
         small[7] is <llong>, small[7] == -5LL);
  int min_int = INT_MIN;
  long min_long = LONG_MIN;
  long long min_llong = LLONG_MIN;
  int same_width = sizeof(long) == sizeof(long long);
  Var expected_long = same_width ? (Var) min_long : (Var) min_llong;
  printf("%d %d %d %d %d %d\n", minima[0] is <i32>, minima[0] == min_int,
         same_width ? minima[1] is <long> : minima[1] is <llong>,
         minima[1] == expected_long,
         minima[2] is <llong>, minima[2] == min_llong);
  int n = -5;
  List runtime = %($n), literal = %(-5);
  printf("%d %d\n", runtime == literal, small[1] == 5);
  match (runtime) {
    case %(-5): puts("matched");
    default: puts("missed");
  }
  return 0;
}
