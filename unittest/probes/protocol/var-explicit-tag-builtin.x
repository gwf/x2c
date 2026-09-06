#include "x2c.x"

typedef struct BuiltinTagClaim { int value; } *BuiltinTagClaim;

Var BuiltinTagClaim.var(BuiltinTagClaim value) {
  return Var.new(<list>, value);
}

BuiltinTagClaim Var.builtintagclaim(Var value) {
  return (BuiltinTagClaim) value.pointer();
}

String BuiltinTagClaim.str(BuiltinTagClaim value) {
  (void) value;
  return %"claim";
}

protocol Var(BuiltinTagClaim) tag <list>;

int main(void) {
  printf("reached main\n");
  return 0;
}
