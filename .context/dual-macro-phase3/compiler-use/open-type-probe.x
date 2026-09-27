#include "x2c.x"
#include <stdio.h>
typedef long double CompilerOpenType;
int main(void) {
  typedef int CompilerOpenType;
  CompilerOpenType value = 33;
  try { assert(value == 33); }
  finally {}
  puts("compiled open global Type cast with caller typedef preserved PASS");
  return 0;
}
