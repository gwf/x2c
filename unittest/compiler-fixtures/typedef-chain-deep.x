// A legal terminating typedef chain must resolve, not trip the
// resolver depth bound.  Paired with typedef-cycle.x, which proves
// the bound still catches a chain that never terminates.
#include "x2c.x"
#include <stdio.h>

typedef int T0;
typedef T0 T1;
typedef T1 T2;
typedef T2 T3;
typedef T3 T4;
typedef T4 T5;
typedef T5 T6;
typedef T6 T7;
typedef T7 T8;
typedef T8 T9;
typedef T9 T10;
typedef T10 T11;
typedef T11 T12;
typedef T12 T13;
typedef T13 T14;
typedef T14 T15;
typedef T15 T16;
typedef T16 T17;
typedef T17 T18;
typedef T18 T19;
typedef T19 T20;
typedef T20 T21;
typedef T21 T22;
typedef T22 T23;
typedef T23 T24;
typedef T24 T25;
typedef T25 T26;
typedef T26 T27;
typedef T27 T28;
typedef T28 T29;
typedef T29 T30;
typedef T30 T31;
typedef T31 T32;
typedef T32 T33;
typedef T33 T34;
typedef T34 T35;
typedef T35 T36;
typedef T36 T37;
typedef T37 T38;
typedef T38 T39;

int main(void) {
  T39 value = 40;
  printf("%d\n", value);
  return 0;
}
