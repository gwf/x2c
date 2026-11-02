#include "x2c.x"
#include "meta.x"

/* A Type hole takes type syntax, a List such as %(long). A bare Symbol
   names no type, so applying a macro value to one is reported where the
   code lands. */
macro Stmt $declare(Type $type) {
  { $type value = 3; printf("%d\n", (int) value); }
}

meta static List declaration(void) {
  Macro declare = $declare;
  return declare(<long>);
}

macro Stmt $declared() { @declaration() }

int main(void) {
  $declared();
  return 0;
}
