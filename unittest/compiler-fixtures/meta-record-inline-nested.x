#include "x2c.x"

struct NestedValue { int value; };
struct NestedBox { struct NestedValue nested; int tail; };

meta struct NestedBox nested_box(int value) {
  struct NestedBox result = {
    .nested = { .value = value },
    .tail = value + 1
  };
  return result;
}

meta int nested_value_probe(int offset) {
  struct NestedBox outer = nested_box(7 + offset);
  struct NestedValue copy = outer.nested;
  copy.value += outer.tail;
  return copy.value;
}

meta int inline_record_probe(int offset) {
  struct { int left; int right; } pair = {
    .left = 4 + offset, .right = 6
  };
  int *alias = &pair.left;
  pair.left += pair.right;
  return *alias;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d %d %d\n",
         $nested_value_probe(0), nested_value_probe(argc - 1),
         $inline_record_probe(0), inline_record_probe(argc - 1));
  return 0;
}
