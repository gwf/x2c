#include "x2c.x"

struct PointerBox { int *pointer; };
struct ConstPointerBox { const int *pointer; };
meta static int pointer_target = 5;

meta struct PointerBox pointer_box(int *pointer) {
  struct PointerBox result = { .pointer = pointer };
  return result;
}

meta int pointer_field_probe(int offset) {
  pointer_target += offset;
  struct PointerBox first = pointer_box(&pointer_target);
  *first.pointer += 2;
  struct PointerBox copy = first;
  *copy.pointer += 3;
  return pointer_target;
}

meta int pointer_qualifier_probe(int offset) {
  int value = 11 + offset;
  const int *alias = &value;
  struct ConstPointerBox box = { .pointer = &value };
  return *alias + *box.pointer;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d %d %d\n",
         $pointer_field_probe(0), pointer_field_probe(argc - 1),
         $pointer_qualifier_probe(0), pointer_qualifier_probe(argc - 1));
  return 0;
}
