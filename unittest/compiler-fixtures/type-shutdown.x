#include "x2c.x"
#include <stdio.h>

typedef struct ShutdownFixture *ShutdownFixture;

static int initialized;

void ShutdownFixture.initialize(void) {
  initialized++;
  puts("initialize");
}

void ShutdownFixture.shutdown(void) {
  printf("shutdown %d\n", initialized);
}

int main(void) {
  ShutdownFixture.initialize();
  ShutdownFixture.initialize();
  puts("main");
  return initialized == 1 ? 0 : 1;
}
