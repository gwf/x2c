#include "x2c.x"

typedef struct Box { int value; } *Box;

// A macro body installs no bindings, so its ordinary locals must still group
// with parentheses instead of reading as casts to an unknown type.
macro Unit $define_grouping(Type $box) => {
  static int $box._power_of_two(unsigned n) {
    if (n < 2 || (n & (n - 1))) return 0;
    return ((n)) != 0;
  }

  static int $box._scaled(unsigned n, void *pointer) {
    int product = (n * (n - 1));
    $box box = ($box) pointer;
    Box alias = (Box) pointer;
    return product + (box == alias);
  }
}

$define_grouping(Box);

int main(void) {
  struct Box box = { 7 };
  printf("%d %d %d %d\n",
         Box__power_of_two(8), Box__power_of_two(6),
         Box__scaled(5, &box), ((box.value)));
  return 0;
}
