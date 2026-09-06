#include "x2c.x"

int main(void) {
  Var source = 3.75;
  char plain = source;
  signed char signed_byte = source;
  unsigned char byte = source;
  short signed_short = source;
  unsigned short short_value = source;
  int signed_int = source;
  unsigned int_value = source;
  long signed_long = source;
  unsigned long long_value = source;
  long long signed_long_long = source;
  unsigned long long long_long_value = source;
  float single = source;
  double real = source;
  long double extended = source;
  printf("%d,%d,%u,%d,%u,%d,%u,%ld,%lu,%lld,%llu,%.2f,%.2f,%.2Lf\n",
         plain, signed_byte, byte, signed_short, short_value, signed_int,
         int_value, signed_long, long_value, signed_long_long,
         long_long_value, single, real, extended);
  return 0;
}
