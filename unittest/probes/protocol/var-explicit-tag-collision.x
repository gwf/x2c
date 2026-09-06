#include "x2c.x"

typedef struct ExplicitCollisionOne { int value; } *ExplicitCollisionOne;
typedef struct ExplicitCollisionTwo { int value; } *ExplicitCollisionTwo;

Var ExplicitCollisionOne.var(ExplicitCollisionOne value) {
  return Var.new(<sharedtag>, value);
}

Var ExplicitCollisionTwo.var(ExplicitCollisionTwo value) {
  return Var.new(<sharedtag>, value);
}

ExplicitCollisionOne Var.explicitcollisionone(Var value) {
  return (ExplicitCollisionOne) value.pointer();
}

ExplicitCollisionTwo Var.explicitcollisiontwo(Var value) {
  return (ExplicitCollisionTwo) value.pointer();
}

String ExplicitCollisionOne.str(ExplicitCollisionOne value) {
  (void) value;
  return %"one";
}

String ExplicitCollisionTwo.str(ExplicitCollisionTwo value) {
  (void) value;
  return %"two";
}

protocol Var(ExplicitCollisionOne) tag <sharedtag>;
protocol Var(ExplicitCollisionTwo) tag <sharedtag>;

int main(void) {
  printf("reached main\n");
  return 0;
}
