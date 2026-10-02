#include "x2c.x"

static int calls, attempts, cleanups;
static int make_value(void) { calls++; return 42; }

static int returned(void) {
  return ({ static int n = make_value(); n++; });
}

static int initialized(void) {
  int value = ({
    static int n = make_value();
    static int other = n + 3;
    int copy = n++;
    { int n = 3; copy += n; }
    copy + other;
  });
  return value;
}

static int nested(void) {
  return ({
    static int n = ({ static int inner = make_value(); inner++; });
    n++;
  });
}

static int fail_once(void) {
  if (++attempts == 1) raise %(retry);
  return 42;
}

static int retried(void) {
  int value = ({ static int n = fail_once(); n++; });
  return value;
}

static int early(int leave) {
  defer cleanups++;
  return ({ static int n = make_value(); if (leave) return -1; n++; });
}

static int loop(void) {
  int total = 0;
  for (int i = 0; i < 5; i++)
    total += ({
      static int n = make_value();
      if (i == 1) continue;
      if (i == 3) break;
      n++;
    });
  return total;
}

static int *addressed(void) {
  return ({ static int n = make_value(); &n; });
}

#define CHECK_VOID(value) \
  _Static_assert(__builtin_types_compatible_p(__typeof__(value), void), \
                 "statement expression must remain void")
static void empty(void) {
  CHECK_VOID(({ static int n = make_value(); }));
  CHECK_VOID(({ static int n = make_value(); ; }));
  ({ static int n = make_value(); });
}

int main(void) {
  int a = returned(), b = returned();
  int c = initialized(), d = initialized();
  int e = nested(), f = nested();
  int caught = 0;
  try { retried(); }
  catch %(retry): caught = 1;
  int g = retried(), h = retried();
  int kept = early(0), left = early(1), total = loop();
  int *first = addressed(), *second = addressed();
  empty();
  printf("%d %d %d %d %d %d\n", a, b, c, d, e, f);
  printf("%d %d %d %d %d %d %d %d %d %d\n", caught, g, h, attempts,
    kept, left, cleanups, total, first == second, *first);
  printf("calls %d\n", calls);
  return 0;
}
