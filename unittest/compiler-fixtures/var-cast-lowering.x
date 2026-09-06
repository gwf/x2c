#include "x2c.x"

int main(void) {
  Var boxed = 5;
  int unboxed = (int) boxed;
  Var round_trip = (Var) (unboxed + 1);
  printf("%d %d\n", unboxed, round_trip.int());
  return unboxed == 5 && round_trip.int() == 6 ? 0 : 1;
}
