int architecture_b(int value);

int architecture_shared(int value) { return value; }

static int architecture_left_leaf(int value) { return value + 1; }

static int architecture_left(int value) {
  return architecture_left_leaf(value);
}

static int architecture_right_leaf(int value) { return value + 2; }

static int architecture_right(int value) {
  return architecture_right_leaf(value);
}

static int architecture_bridge(int value) {
  return architecture_left(value) + architecture_right(value);
}

static int architecture_root(int value) {
  return architecture_bridge(value);
}

static int architecture_detached_leaf(int value) { return value + 3; }

static int architecture_detached(int value) {
  return architecture_detached_leaf(value);
}

static int architecture_isolated(int value) { return value + 4; }

static int architecture_to_b(int value) {
  return architecture_b(value) + architecture_b(value);
}
