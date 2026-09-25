#include "x2c.x"
#include "typed-array.x"
#include "typed-map.x"

/* Typed Array and Map conversions run in a meta body as they do at run
   time: the destination packs the literal and boxes the result. */
meta String packed_ints(int n) {
  ArrayInt values = [n, n + 1];
  Var boxed = values;
  ArrayInt back = boxed;
  Var again = back;
  return %"${boxed.repr()} ${again.repr()}";
}

meta String packed_map(int n) {
  MapStringInt counts = {"k": n};
  Var boxed = counts;
  MapStringInt back = boxed;
  Var again = back;
  return %"${boxed.repr()} ${again.repr()}";
}

int main(int argc, char **argv) {
  (void) argv;
  printf("array %s | %s\n", $packed_ints(4), packed_ints(argc + 3));
  printf("map %s | %s\n", $packed_map(2), packed_map(argc + 1));
  return 0;
}
