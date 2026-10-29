#include "x2c.x"

// An expansion is rescanned for further uses, a nested use expands inside
// an argument, and a macro never expands within its own expansion.
#define LIMIT LIMIT_VALUE
#define LIMIT_VALUE 4
#define TWICE(x) ((x) + (x))
#define APPLY(f, v) f(v)
#define self self
#define ping pong
#define pong ping

int main(void) {
  int self = 1, ping = 2;
  printf("%d %d %d %d\n", LIMIT, TWICE(TWICE(1)), APPLY(TWICE, 3),
         self + ping);
  return 0;
}
