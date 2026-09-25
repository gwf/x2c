/* A pointer reaches a reference parameter only through `*p`. */
#include <stdio.h>

static void set(int &x) { x = 5; }

int main(void) {
  int value = 0;
  int *pointer = &value;
  set(*pointer);
  set(pointer);
  return value;
}
