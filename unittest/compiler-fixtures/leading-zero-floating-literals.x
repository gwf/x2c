#include <stdio.h>

int main(void) {
  double fraction = 01.5, exponent = 017e3, nonoctal = 09.5;
  int octal = 017;
  printf("%g %g %g %d\n", fraction, exponent, nonoctal, octal);
  return 0;
}
