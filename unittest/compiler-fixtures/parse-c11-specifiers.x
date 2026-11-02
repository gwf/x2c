/*  parse-c11-specifiers.x -- C11's `_Alignas`, `_Atomic`, and `_Complex`
    pass to C as written, and C gives them their meaning.
*/
#include "x2c.x"
#include <complex.h>
#include <stdatomic.h>

_Alignas(16) static int aligned = 1;
static _Atomic int counter = 0;
static _Atomic(long) total = 5;

typedef struct Slot { _Alignas(32) char bytes[8]; } Slot;

static void bump(_Atomic int *target, int by) {
  atomic_fetch_add(target, by);
}

static double _Complex twice(_Complex double z) => z * 2.0;

int main(void) {
  _Alignas(double) char buffer[sizeof(double)];
  buffer[0] = 3;
  bump(&counter, 2);
  counter += 3;
  total = total + counter;
  double _Complex z = twice(1.0 + 2.0 * I);
  printf("%d %d %d %ld\n", aligned, buffer[0], (int) counter, (long) total);
  printf("%g %g\n", creal(z), cimag(z));
  printf("%d %d %d\n", sizeof(_Atomic int) == sizeof(int),
         sizeof(_Complex double) == 2 * sizeof(double), (int) _Alignof(Slot));
  return 0;
}
