#include "x2c.x"

int main(void) {
  Var increment = 1;
  char plain = 1;
  signed char signed_byte = 1;
  unsigned char byte = 1;
  short signed_short = 1;
  unsigned short short_value = 1;
  volatile int observed = 2;
  unsigned int_value = 1;
  long signed_long = 1;
  unsigned long long_value = 1;
  long long signed_long_long = 1;
  unsigned long long long_long_value = 1;
  float single = 1.0f;
  double real = 1.0;
  long double extended = 1.0L;
  const int fixed = 3;
  register int local = 4;
  plain += increment;
  signed_byte += increment;
  byte += increment;
  signed_short += increment;
  short_value += increment;
  observed += increment;
  int_value += increment;
  signed_long += increment;
  long_value += increment;
  signed_long_long += increment;
  long_long_value += increment;
  single += increment;
  real += increment;
  extended += increment;
  fixed += increment;
  local += increment;
  return observed;
}
