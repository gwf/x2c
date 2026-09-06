#include "public-target.x"

typedef int (*Callback)(int);

typedef struct CallbackHolder {
  Callback callback;
} CallbackHolder;

static int helper(int value) {
  return value + 1;
}

static int direct(void) {
  return helper(1);
}

static int recursive(int value) {
  return value ? recursive(value - 1) : 0;
}

static int resolved_method(String value) {
  return value.len();
}

static int indirect(Callback callback) {
  return callback(1);
}

static int computed(CallbackHolder *holder) {
  return holder->callback(1);
}

static int expanded(List values) {
  int count = 0;
  foreach (Var value, values) count += value.truthy();
  return count;
}

static int initialized = helper(2);

int call_public_target(void) {
  return public_target();
}
