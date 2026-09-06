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
