#include "x2c.x"

meta int native_scalar_pointer_probe(int offset) {
  int exponent = 0;
  double fraction = frexp(20.0, &exponent);
  return (int) (fraction * 100.0) + exponent + offset;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $native_scalar_pointer_probe(0),
         native_scalar_pointer_probe(argc - 1));
  return 0;
}
