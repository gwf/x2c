#include "x2c.x"

struct AssignmentPoint { int x; };
struct AssignmentPointer { int *field; };

meta int assignment_alias(void) {
  struct AssignmentPoint a = { .x = 1 }, b = { .x = 2 };
  int *field = &a.x;
  a = b;
  return *field * 10 + a.x;
}

int native_assignment_alias(void) {
  struct AssignmentPoint a = { .x = 1 }, b = { .x = 2 };
  int *field = &a.x;
  a = b;
  return *field * 10 + a.x;
}

meta int pointer_identity(void) {
  struct AssignmentPoint record = { .x = 7 };
  int *alias = &record.x;
  struct AssignmentPointer holder = { .field = &record.x };
  Var boxed = &record.x;
  Var same = &record.x;
  return (&record.x == &record.x) +
         10 * (&record == &record) +
         100 * (alias == &record.x) +
         1000 * (holder.field == &record.x) +
         10000 * (boxed == same);
}

int main(void) {
  int runtime = 1;
  printf("%d %d %d %d\n",
         $(assignment_alias), native_assignment_alias(),
         $(pointer_identity), runtime ? pointer_identity() : 0);
  return 0;
}
