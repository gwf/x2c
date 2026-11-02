#include "x2c.x"

/* A lambda adapted to a C callback keeps the callback's whole signature: a
   result of several words, a qualified pointer result named by a typedef or
   spelled in the parameter's declarator, or no parameters. */

typedef unsigned long (*Widen)(int);
typedef long long (*Shift)(long long);
typedef const char *(*Namer)(int);
typedef int (*Thunk)(void);

static unsigned long call_widen(Widen f, int x) => f(x);
static long long call_shift(Shift f, long long x) => f(x);
static const char *call_namer(Namer f, int x) => f(x);
static const char *call_spelled(const char *(*f)(int), int x) => f(x);
static int call_thunk(Thunk f) => f();

int main(void) {
  printf("%lu\n", call_widen(%!(int x) => (unsigned long) x << 40, 1));
  printf("%lld\n", call_shift(%!(long long x) => x << 33, 1));
  printf("%s\n", call_namer(%!(int x) => x ? "yes" : "no", 1));
  printf("%s\n", call_spelled(%!(int x) => x ? "spelled" : "no", 1));
  printf("%d\n", call_thunk(%!() => 42));
  return 0;
}
