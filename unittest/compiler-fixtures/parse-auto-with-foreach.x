/*  parse-auto-with-foreach.x -- a statement-start `auto` opens a region
    before `with (...)` and `foreach (...)`, while `auto with = 5` and
    `auto foreach = 6` infer locals named `with` and `foreach`.
*/
#include "x2c.x"

static int released;
static void drop(void *value) { released += *(int *) value; }
static void acquire(int value) {
  int *p = Scope.malloc_finalized(sizeof(int), drop);
  *p = value;
}

int main(void) {
  int level = 0;
  auto with (level = 1) { acquire(level); }
  auto foreach (int value in %(2 3)) acquire(value);
  printf("regions %d %d\n", level, released);
  auto with = 5;
  auto foreach = 6;
  printf("locals %d %d\n", with, foreach);
  return 0;
}
