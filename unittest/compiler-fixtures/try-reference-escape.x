#include "x2c.x"

/* A local a `try` body passes by reference keeps its type, so the call
   discards no qualifier, and its address escapes at its declaration, so the
   catch sees what the callee wrote before it raised. */

static void bump(int &n) { n = n + 1; }

static void set_and_raise(int &n, int value) {
  n = value;
  raise %(bad-arg);
}

static void parameter(int n) {
  try {
    n = 1;
    set_and_raise(n, 4);
  }
  catch %(bad-arg *): printf("parameter %d\n", n);
}

int main(void) {
  int status = 0, plain = 0;
  try {
    status = 1;
    plain = 1;
    bump(status);
    set_and_raise(status, status + 1);
  }
  catch %(bad-arg *): printf("status %d %d\n", status, plain);
  int written = 0;
  try set_and_raise(written, 3);
  catch %(bad-arg *): printf("written %d\n", written);
  parameter(0);
  for (int i = 0; i < 1; i++)
    try set_and_raise(i, 5);
    catch %(bad-arg *): printf("loop %d\n", i);
  return 0;
}
