#include "x2c.x"

typedef struct Vec {
  int x;
  int y;
} *Vec;

/* A complete Var conversion pair AND a protocol member implementation --
   everything the old inference path needed to confer Var membership on
   Vec.  Participation is now DECLARED, not inferred: without a
   `protocol Var(Vec);` adoption row Vec does not participate, so a
   base-default protocol member (resolved through the conformance table)
   is not available on Vec and the dot call fails with the ordinary
   no-method error. */

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
