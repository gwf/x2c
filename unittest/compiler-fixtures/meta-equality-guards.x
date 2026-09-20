#include "x2c.x"

meta int int_guard(int value) {
  if (value) return 1;
  return 0;
}

meta int list_guard(List value) {
  if (value) return 1;
  return 0;
}

meta int list_equal(List left, List right) {
  if (left.equal(right)) return 1;
  return 0;
}

meta Var next_value(Map state) {
  state["calls"] = state["calls"] + 1;
  return state["calls"];
}

meta int equality_effect(void) {
  Map state = {};
  state["calls"] = 0;
  int result = 0;
  if (next_value(state).equal(1)) result = 1;
  return 10 * (int) state["calls"] + result;
}

int main(void) {
  printf("scalar %d %d %d\n", $(int_guard 0), $(int_guard 0.0),
         $(int_guard 2));
  printf("list %d %d %d\n", $(list_guard nil), $(list_guard 0),
         $(list_guard '(1)));
  printf("equal %d %d %d\n", $(list_equal nil nil),
         $(list_equal '(1) '(1)), $(list_equal '(1) '(2)));
  printf("effects %d\n", $(equality_effect));
}
