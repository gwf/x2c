#include "x2c.x"

struct BoxedScalar { long double value; };

meta Array boxed_scalar_values(int offset) {
  struct BoxedScalar record = { .value = 12.5L + offset };
  Array values = [];
  values.push(record.value);
  return values;
}

meta int boxed_scalar_probe(int offset) {
  Array values = boxed_scalar_values(offset);
  Var value = values[0];
  return value is <ldouble> && value.long_double_value() == 12.5L
       ? 125 : 0;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $boxed_scalar_probe(0),
         boxed_scalar_probe(argc - 1));
  return 0;
}
