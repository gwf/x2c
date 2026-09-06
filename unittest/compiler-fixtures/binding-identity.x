#include "x2c.x"

typedef int binding_phase5_Base;
typedef binding_phase5_Base binding_phase5_Value;

typedef struct binding_phase5_Box {
  binding_phase5_Value value;
} binding_phase5_Box;

binding_phase5_Value binding_phase5_global = 1;

binding_phase5_Value binding_phase5_shadow(binding_phase5_Value value) {
  binding_phase5_Value result = value;
  {
    binding_phase5_Value value = 2;
    result += value;
  }
  return result + value + binding_phase5_global;
}

binding_phase5_Value binding_phase5_Box.bump(
  binding_phase5_Box box, binding_phase5_Value value) {
  return box.value + value;
}

int main(void) {
  binding_phase5_Box box = {.value = 3};
  binding_phase5_Value value = binding_phase5_shadow(4);
  Var lambda = (%!(value) => value.int() + 1)(5);
  if (value != 11) return 1;
  if (box.bump(2) != 5) return 2;
  if (lambda.int() != 6) return 3;
  return 0;
}
