#include "x2c.x"

// `##` makes the names x2c declares and calls, including a function with
// an expression body.
#define NAME(n) fn_##n
#define COUNTER(kind) kind##_count

int NAME(a)(void) { return 1; }
int NAME(b)(void) => 2;
static int COUNTER(apple) = 5;

int main(void) {
  printf("%d %d %d\n", NAME(a)(), NAME(b)(), COUNTER(apple));
  return 0;
}
