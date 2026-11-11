#include "x2c.x"
#include "meta.x"

// Each row of an `expand` applies a macro whose body splices a meta result.
meta static List constant(String name) {
  List function = x2c_ident(name);
  List unit = $!Unit{ int $function(void) { return 1; } };
  return $(unit);
}

expand %("one" "two")
macro Unit(Literal $name) { @constant($name) }

int main(void) {
  printf("%d\n", one() + two());
  return 0;
}
