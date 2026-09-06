#include "x2c.x"

typedef struct StaticGap {
  int value;
} *StaticGap;

Var StaticGap.var(StaticGap value) {
  return Var.new(<staticgap>, value);
}

StaticGap Var.staticgap(Var value) {
  return value.pointer();
}

protocol Var(StaticGap);

int main(void) {
  StaticGap value = Scope.malloc(sizeof(struct StaticGap));
  return (int) value.hash();
}
