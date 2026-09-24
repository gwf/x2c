static int tail_only(List value, int count) {
  if (!value) return count;
  return tail_only(value.cdr(), count + 1);
}

static int mixed_tail(List value) {
  if (!value) return 0;
  if (value.car()) return mixed_tail(value.cdr());
  return 1 + mixed_tail(value.cdr());
}

static int cleanup_tail(List value, int count) {
  defer count++;
  if (!value) return count;
  return cleanup_tail(value.cdr(), count);
}

static int non_tail_only(List value) {
  return value ? 1 + non_tail_only(value.cdr()) : 0;
}

static int conditional_tail(int n) {
  return n ? conditional_tail(n - 1) : 0;
}

static int nested_conditional_tail(int n) {
  return n > 2 ? nested_conditional_tail(n - 1)
               : n ? nested_conditional_tail(n - 1) : 0;
}

static int conditional_mixed(int n) {
  return conditional_mixed(n - 1) ? conditional_mixed(n - 2)
                                  : 1 + conditional_mixed(n - 3);
}

static int conditional_cleanup(int n) {
  defer n++;
  return n ? conditional_cleanup(n - 1) : 0;
}

static int conditional_condition_only(int n) {
  return conditional_condition_only(n - 1) ? n : 0;
}

static int conditional_non_tail(int n) {
  return 1 + (n ? conditional_non_tail(n - 1) : 0);
}
