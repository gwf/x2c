#include "x2c.x"

typedef struct Slot {
  int value;
} *Slot;

Var Slot.var(Slot value) {
  return Var.new(<slot>, value);
}

Slot Var.slot(Var value) {
  return (Slot) value.pointer();
}

Slot Slot.new(int value) {
  Slot result = Scope.malloc(sizeof(struct Slot));
  result.value = value;
  return result;
}

Var Slot.getindex(Slot value, int key) {
  if (key != 0) return void;
  return value.value;
}

Var Slot.setindex(Slot value, int key, Var replacement) {
  if (key != 0) return void;
  value.value = replacement.integer();
  return replacement;
}

Var Slot.updateindex(Slot value, int key, Symbol op, Var rhs) {
  if (key != 0 || op != <+>) return void;
  value.value += rhs.integer();
  return value.value;
}

Var Slot.postfixindex(Slot value, int key, Symbol op) {
  if (key != 0 || op != <++>) return void;
  return value.value++;
}

protocol Var(Slot);

int main(void) {
  Slot direct = Slot.new(3), boxed_value = Slot.new(3);
  Var boxed = boxed_value;
  Var direct_before = direct.postfixindex(0, <++>);
  Var boxed_before = boxed.postfixindex(0, <++>);
  direct.setindex(0, 8);
  boxed.setindex(0, 8);
  direct.updateindex(0, <+>, 2);
  boxed.updateindex(0, <+>, 2);
  printf(
    "%ld %ld %ld %ld %d %d\n",
    direct_before.integer(), boxed_before.integer(),
    direct.getindex(0).integer(), boxed.getindex(0).integer(),
    direct.value, boxed.slot().value
  );
  return 0;
}
