/* Conversions that the pointer-level check leaves to C: an Array into a
   `void *` field, a String into a `const char *` field, an argument vector
   into a `char **` field, and an Array into an `Array` field. */

#include "x2c.x"

typedef struct Slots {
  void *opaque;
  const char *name;
  char **argv;
  Array items;
} Slots;

int main(int argc, char **argv) {
  Array items = [1, 2, 3];
  String name = "slots";
  Slots s = { items, name, argv, items };
  printf("%d %s %d %d\n", s.opaque == (void *) items, s.name, s.argv == argv,
         (int) s.items.len());
  return argc == 1 ? 0 : 1;
}
