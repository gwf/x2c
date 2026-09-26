#include "x2c.x"

struct AssignmentPoint { int x; };
struct AssignmentPointer { int *field; };

$(import "meta-record-assignment-alias.xmacro")

int native_assignment_alias(void) {
  struct AssignmentPoint a = { .x = 1 }, b = { .x = 2 };
  int *field = &a.x;
  a = b;
  return *field * 10 + a.x;
}

int main(void) {
  int runtime = 1;
  printf("%d %d %d %d\n",
         $(assignment_alias), native_assignment_alias(),
         $(pointer_identity), runtime ? pointer_identity() : 0);
  return 0;
}
