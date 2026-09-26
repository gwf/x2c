#include "x2c.x"

meta int next_value(Iter iter, Var *out) {
  int value = iter.state.int();
  if (value > 3) return 0;
  iter.state = value + 1;
  *out = value;
  return 1;
}

meta int user_kernel_probe(int offset) {
  struct Iter storage;
  Iter values = Iter.init(&storage, void, next_value, 1 + offset);
  Var first, second, third, extra;
  if (!values.try_next(first) || !values.try_next(second) ||
      !values.try_next(third) || values.try_next(extra)) return -1;
  return first.int() * 100 + second.int() * 10 + third.int();
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $user_kernel_probe(0),
         user_kernel_probe(argc - 1));
  return 0;
}
