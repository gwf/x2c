#include "after.x"

macro Declaration $declaration(Type $type, DeclaratorRow $row) {
  $type $row;
}

/* This translation unit explicitly observes every initialized local. */
$after_initialization($declaration)
meta Code observe_initialization(Code declaration) {
  return $!{ puts("initialized"); };
}

int main(void) {
  {
    const struct { int value; } first = {4}, second = first;
    printf("qualified %d %d\n", first.value, second.value);
  }
  {
    enum { one = 1 } first = one, second = first;
    printf("enum %d %d\n", first, second);
  }
  {
    static const struct { int value; } first = {4}, second = {5};
    printf("static %d %d\n", first.value, second.value);
  }
  {
    int values[2] = {1, 2}, *pointer = values;
    printf("modifiers %d %d\n", values[1], *pointer);
  }
  return 0;
}
