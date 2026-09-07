#include "x2c.x"

typedef struct Vec {
  int x;
  int y;
} *Vec;

/* A Var conversion pair and a protocol member implementation do not confer
   Var membership on Vec. Without a `protocol Var(Vec);` adoption row, Vec
   does not participate; a base-default protocol member is unavailable and
   the dot call fails with the ordinary no-method error. */

Var Vec.var(Vec v) {
  return Var.new(<vec>, v);
}

Vec Var.vec(Var v) {
  return (Vec) v.pointer();
}

String Vec.str(Vec v) {
  return %"Vec(${v.x},${v.y})";
}

int main(void) {
  Vec v = Scope.malloc(sizeof(struct Vec));
  v.x = 1;
  v.y = 2;
  /* `hash` is a Var protocol member Vec does not implement. An adoption row
     would leave its descriptor slot empty for dynamic fallback, but would
     not grant Vec a static method. Without one, Vec is not a participant. */
  printf("%u\n", v.hash());
  return 0;
}
