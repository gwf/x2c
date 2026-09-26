/* Numeric literals and C-style array initialization agree in both forms. */
#include "x2c.x"

meta static int numeric_literals(int n) {
  unsigned long long top = 18446744073709551615ULL;
  long wide = 10000000000L;
  long double fraction = 9.0L;
  return (top == 0xffffffffffffffffULL) + (wide > 2000000000L)
    + (int) fraction + (int) (0x1.8p2L) + 0b10U + 0o10UL + 010LL + n;
}

meta static int numeric_precision(int n) {
  float rounded = 16777217.0F;
  return (int) ((double) rounded - 16777216.0) + n;
}

meta static int array_unsigned(int n) {
  unsigned char values[2U] = {n};
  return values[0] + values[1];
}

meta static int array_signed(int n) {
  signed char values[2] = {n, -n};
  return values[0] - values[1];
}

meta static int array_float(int n) {
  float values[2] = {16777217.0 + n};
  return (int) ((double) values[0] - 16777216.0 + values[1]);
}

meta static int array_integer(int n) {
  int values[2] = {3.9 + n, -3.9 - n};
  return values[0] - values[1];
}

meta static String joined(void) => "ab" "c\"d" "\x41" "B";

meta static double negated(double z) => -z;

meta static int reciprocal_sign(double z) => 1.0 / z < 0;

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
