int architecture_shared(int value);

static int architecture_b_helper(int value) {
  return architecture_shared(value);
}

int architecture_b(int value) {
  return architecture_shared(value) + architecture_b_helper(value);
}
