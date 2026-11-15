#include "x2c.x"

/* Fields have their own names even when an enclosing scope has an alias. */
macro Field $nested(Name $name, Name $field) {
  struct { int $field; } $name;
}

alias 9 as size;
struct Outer {
  int size;
  alias 4 as width;
  alias 1 {
    struct Inner {
      int width;
      alias 2 { int size; }
    } inner;
    $nested(other, width);
    int cells[width];
  }
};

int main(void) {
  struct Outer value = { .size = 3, .inner = { .width = 5, .size = 7 },
    .other = { .width = 11 } };
  printf("%d %d %d %d %d\n", value.size, value.inner.width,
    value.inner.size, value.other.width, (int) (sizeof(value.cells) / sizeof(int)));
  return 0;
}
