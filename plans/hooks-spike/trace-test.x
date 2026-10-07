#include "trace.x"

static int square(int n) => n * n;

int fact(int n) {
  if (n <= 1) return 1;
  return n * fact(n - 1);
}

void greet(String name) {
  printf("hello %s\n", name);
}

int main(void) {
  greet("trace");
  return square(fact(3)) == 36 ? 0 : 1;
}
