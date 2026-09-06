#include "x2c.x"

typedef int (*StaticCallback)(int);

static StaticCallback callbacks[] = { &add_one };

static int add_one(int value) {
  return value + 1;
}

int main(void) {
  int result = callbacks[0](41);
  printf("%d\n", result);
  return result == 42 ? 0 : 1;
}
