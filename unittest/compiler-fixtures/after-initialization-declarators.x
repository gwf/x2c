/* Registers a postlude; the compiler retains the declaration sequence. */
#include "meta.x"

meta Code register_after_initialization(Code function, Code pattern) =>
  function.register_after_initialization(pattern.value(), NULL);

macro Decorator $after_initialization(Unit $function, Expr $pattern) {
  @register_after_initialization($function, $pattern)
}

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
  {
    auto int values[2] = { 3, 4 };
    auto pointer = values;
    printf("auto %d\n", pointer[1]);
  }
  return 0;
}
