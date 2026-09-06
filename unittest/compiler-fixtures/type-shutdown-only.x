#include "x2c.x"
#include <stdio.h>

typedef struct ShutdownOnlyFixture *ShutdownOnlyFixture;

void ShutdownOnlyFixture.shutdown(void) {
  puts("shutdown");
}

int main(void) {
  puts("main");
  return 0;
}
