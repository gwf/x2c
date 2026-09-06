#include "x2c.x"

int main(void) {
  Array values = %[10, 20, 30];
  Var dynamic = 1;
  int scalar = 2;
  Var bracket_dynamic = values[dynamic];
  Var method_dynamic = values.getindex(dynamic);
  Var bracket_scalar = values[scalar];
  Var method_scalar = values.getindex(scalar);
  Var bracket_negative = values[-1];
  Var method_negative = values.getindex(-1);
  values[dynamic] = 21;
  values.setindex(dynamic, values.getindex(dynamic).int() + 1);
  values[-1] = 40;
  printf("%d %d\n", bracket_dynamic.int(), method_dynamic.int());
  printf("%d %d\n", bracket_scalar.int(), method_scalar.int());
  printf("%d %d\n", bracket_negative.int(), method_negative.int());
  printf("%d %d\n", values[1].int(), values.getindex(-1).int());
  return 0;
}
