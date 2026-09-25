/* A reference parameter takes an lvalue, never a pointer or null. */
#include <stdio.h>

static void set(int &x) { x = 5; }

int main(void) {
  int value = 0;
  set(NULL);
  return value;
}
