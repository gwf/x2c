/* Numeric literals and C-style array initialization agree in both forms. */
#include "x2c.x"

$(import "meta-numeric-lowering.xmacro")

int main(int argc, char **argv) {
  int n = argc - 1;
  (void) argv;
  printf("literals %d %d\n", $(numeric_literals 0), numeric_literals(n));
  printf("precision %d %d\n", $(numeric_precision 0), numeric_precision(n));
  printf("unsigned %d %d\n", $(array_unsigned 257), array_unsigned(n + 257));
  printf("signed %d %d\n", $(array_signed 129), array_signed(n + 129));
  printf("float %d %d\n", $(array_float 0), array_float(n));
  printf("integer %d %d\n", $(array_integer 0), array_integer(n));
  printf("joined %s %s\n", $joined(), joined());
  printf("negated %g %g\n", $negated(0.0), negated(n + 0.0));
  printf("sign %d %d %d\n", $reciprocal_sign(0.0), $reciprocal_sign(-0.0),
         reciprocal_sign(n + 0.0));
  return 0;
}
