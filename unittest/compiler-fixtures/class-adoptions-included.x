// An including unit sees every adoption a class generates, although the
// class declares them all at one location.
#include "x2c.x"
#include "class-adoptions-included/box.x"

int main(void) {
  Box box = $auto(Box.new(3));
  Var value = box;
  printf("%s\n", (char *) value.repr());
  return 0;
}
