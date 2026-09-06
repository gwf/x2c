#include "x2c.x"
#include <stdio.h>
#include <stdlib.h>

typedef void *Handle;

protocol void *(T) {
  void T.release(T) = free;
}

protocol void *(Handle);

int main(void) {
  Handle handle = malloc(1);
  handle.release();
  puts("ok");
  return 0;
}
