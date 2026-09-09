#include "x2c.x"

#define WIDTH (sizeof(int) / sizeof(int) + 1)
struct Payload { int value; };
struct Leaf { int value; };
struct Other { struct Payload value; };
struct Outer { struct Leaf values[WIDTH]; struct Other last; };
struct Anonymous { struct { String values[WIDTH]; Var last; } rows[2]; };

int main(void) {
  struct Payload payload = {7};
  struct Outer value = {.values[WIDTH - 2] = {1}, {2}, {payload}};
  struct Anonymous nested = {
    .rows[0].values[WIDTH - 1] = "one", "tail", {"two", "three", "last"}
  };
  String *first = nested.rows[0].values, *second = nested.rows[1].values;
  printf("%d %d %d %d %d\n", value.values[1].value, value.last.value.value,
    first[1].len(), second[0].len(), second[1].len());
  return 0;
}
