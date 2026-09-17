#include "x2c.x"

/* A block decorator standing before a file-scope function decorates that
   function's body: the region opens around the body and closes on every
   exit, including a return from inside it. */

static int level = 1;

$scope() static int summed(List values, int bias) {
  int sum = bias;
  foreach (Var value, values) sum += value.int();
  if (sum > 100) return -1;
  return sum;
}

$lock(mutex) static void bump(Mutex mutex, int *count) {
  (*count)++;
}

$let(level, 7) static int borrowed(void) {
  return level;
}

int main(void) {
  Mutex mutex = $auto(Mutex.new());
  int count = 0;
  bump(mutex, &count);
  printf("%d %d %d %d\n", summed(%(1 2 3), 10), count, borrowed(), level);
  return 0;
}
