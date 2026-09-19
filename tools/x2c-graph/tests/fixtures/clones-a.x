int clone_combine(int left, int right);
int clone_other(int left, int right);

int clone_alpha_a(int left, int right) {
  int total = clone_combine(left, right);
  return total + 17;
}

int clone_repeated(int left, int right) {
  int total = clone_combine(left, left);
  return total + 17;
}

int clone_literal(int left, int right) {
  int total = clone_combine(left, right);
  return total + 19;
}

int clone_operator(int left, int right) {
  int total = clone_combine(left, right);
  return total - 17;
}

int clone_callee(int left, int right) {
  int total = clone_other(left, right);
  return total + 17;
}

static int clone_private(int value) {
  return value + 23;
}

int clone_static_a(int value) {
  int answer = clone_private(value);
  return answer + 29;
}

int clone_nested_a(int value) {
  int earlier = value + 31;
  if (value > 0) {
    int doubled = clone_combine(value, value);
    return doubled + 37;
  }
  return earlier;
}

int clone_local_prototype_a(int value) {
  extern int clone_target_a(int);
  return clone_target_a(value) + clone_target_a(value + 1) + 23;
}

int clone_local_extern_a(int value) {
  extern int clone_object_a;
  return clone_object_a + value + clone_object_a + 23;
}

int clone_pointer_a(int (*callback)(int), int value) {
  int (*local)(int) = callback;
  return local(value) + local(value + 1) + 23;
}
