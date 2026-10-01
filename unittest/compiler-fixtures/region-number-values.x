#include "x2c.x"

static long as_number(int *p) => (long) (intptr_t) p;
static long id_number(long n) => n;

// A callee turns the address into a number, which holds no address.
long returned_from_callee(void) {
  int count = 1;
  return as_number(&count);
}

// A number passed through a callee holds no address either.
long passed_through_callee(void) {
  int count = 1;
  return id_number((long) (intptr_t) &count);
}

// A cast to a number drops the address.
long returned_cast(void) {
  int count = 1;
  return (long) (intptr_t) &count;
}

// The address itself still reports.
int *returned_address(void) {
  int count = 1;
  return &count;
}
