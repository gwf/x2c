#include "x2c.x"
#include <stdio.h>
static int calls;
double _compiler_open_target(double value) {
  calls++;
  return value;
}
int main(void) {
  int caller_value = 33;
  try { assert(caller_value == 33); }
  finally {}
  assert(calls == 1);
  puts("compiled open target call and preserved caller local PASS");
  return 0;
}
