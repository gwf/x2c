int clone_combine(int left, int right);

int clone_alpha_b(int first, int second) {
  // Spelling, comments, and whitespace do not affect the body match.
  int output = clone_combine(first,second);

  return output + 17;
}

static int clone_private(int input) {
  return input + 23;
}

int clone_static_b(int input) {
  int result = clone_private(input);
  return result + 29;
}

int clone_nested_b(int input) {
  int before = input + 41;
  int another = before + 43;
  if (input > 0) {
    int result = clone_combine(input, input);
    return result + 37;
  }
  return another;
}

int clone_local_prototype_b(int input) {
  extern int clone_target_b(int);
  return clone_target_b(input) + clone_target_b(input + 1) + 23;
}

int clone_local_extern_b(int input) {
  extern int clone_object_b;
  return clone_object_b + input + clone_object_b + 23;
}

int clone_pointer_b(int (*operation)(int), int input) {
  int (*renamed)(int) = operation;
  return renamed(input) + renamed(input + 1) + 23;
}
