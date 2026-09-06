// Ordinary user names survive lowering; the reserved side (declarations
// inside the generated-name space) is covered by reserved-namespace.x.
#include "x2c.x"

static int user_gensym_12 = 1;
static int user_lambda_0 = 2;
static int user_lambda_adapt_0 = 3;
static int user_exception_frame_0 = 4;
static int user_cleanup_guard_0 = 5;
static int user_cleanup_prev_0 = 6;
static int user_cleanup_state_0 = 7;
static int cleaned = 0;

static void record_cleanup(void) {
  cleaned++;
}

static int apply_int(int (*fn)(int)) {
  return fn(1);
}

int main(void) {
  struct { int value; } item = { .value = user_gensym_12 };
  int mapped = apply_int(%!(value) => value.int() + 1);
  try {
    defer record_cleanup();
    raise %(invariant);
  }
  catch %(invariant): {}
  int sentinels = user_lambda_0 + user_lambda_adapt_0 +
                  user_exception_frame_0 + user_cleanup_guard_0 +
                  user_cleanup_prev_0 + user_cleanup_state_0;
  printf("%d %d %d\n", mapped, cleaned, sentinels);
  return mapped == 2 && cleaned == 1 && sentinels == 27 ? 0 : 1;
}
