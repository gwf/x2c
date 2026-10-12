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
  Var dynamic = 1;
  volatile Var changing = 2;
  dynamic += increment;
  ++changing;
  register int native = 1;
  native++;
  int pointed = 1;
  register int *pointer = &pointed;
  pointer[0] += increment;
  return observed == 3 && dynamic == 2 && changing == 3 &&
         native == 2 && pointed == 2 ? 0 : 1;
}
