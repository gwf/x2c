#include "x2c.x"

static int choose(List value, int next) {
  int result = 0;
  if (value ~= %(alpha ?x)) result = x.integer();
  else if (next) { result = 2; }
  else result = 3;
  return result;
}

int main(void) {
  printf("%d %d %d\n", choose(%(alpha 1), 0),
    choose(%(beta 1), 1), choose(%(beta 1), 0));
  return 0;
}
