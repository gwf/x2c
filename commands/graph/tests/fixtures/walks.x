static int first_walk(List value) {
  if (!value) return 0;
  int count = 1;
  foreach (Var child, value)
    if (child is <list>) count += first_walk(child.list());
  return count;
}

static int second_walk(List value) {
  if (!value) return 0;
  int count = 1;
  foreach (Var child, value)
    if (child is <list>) count += second_walk(child.list());
  return count;
}

static int combined_walk(List value) {
  return first_walk(value) + second_walk(value);
}

static int separate_walk(List first, List second) {
  return first_walk(first) + second_walk(second);
}

typedef struct WalkValue {
  List first, second;
} WalkValue;

typedef struct WalkLeaf {
  List nodes;
} WalkLeaf;

typedef struct WalkTree {
  WalkLeaf leaf;
} WalkTree;

typedef struct WalkHolder {
  List field;
} *WalkHolder;

static int field_walk(WalkValue value) {
  return first_walk(value.first) + second_walk((value.first));
}

static int nested_field_walk(WalkTree tree) {
  return first_walk(tree.leaf.nodes) + second_walk(tree.leaf.nodes);
}

static int pointer_field_walk(WalkHolder holder) {
  return first_walk(holder.field) + second_walk(holder.field);
}

static int different_field_walk(WalkValue value) {
  return first_walk(value.first) + second_walk(value.second);
}

static int different_root_walk(WalkValue first, WalkValue second) {
  return first_walk(first.first) + second_walk(second.first);
}

static WalkValue walk_value_identity(WalkValue value) { return value; }

static int call_receiver_walk(WalkValue value) {
  return first_walk(walk_value_identity(value).first) +
         second_walk(walk_value_identity(value).first);
}

static int index_receiver_walk(WalkValue *values) {
  return first_walk(values[0].first) + second_walk(values[0].first);
}

static int dereference_receiver_walk(WalkValue *value) {
  return first_walk((*value).first) + second_walk((*value).first);
}

static int assignment_argument_walk(WalkValue value, List replacement) {
  return first_walk(value.first = replacement) +
         second_walk(value.first = replacement);
}

static int linear_first(List value) {
  int count = 0;
  foreach (Var item, value) if (item) count++;
  return count;
}

static int linear_second(List value) {
  int count = 0;
  foreach (Var item, value) if (!item) count++;
  return count;
}

static int combined_linear_walk(List value) {
  return linear_first(value) + linear_second(value);
}

static int repeated_linear_walk(List value) {
  return linear_first(value) + linear_first(value);
}

static int linear_wrapper(List value) {
  return linear_first(value);
}

static int combined_wrapper_walk(List value) {
  return linear_wrapper(value) + linear_second(value);
}

static int inline_and_len_walk(List value) {
  int count = 0;
  foreach (Var item, value) if (item) count++;
  return count + value.len();
}

static int early_exit_walk(List value) {
  foreach (Var item, value) if (item) return 1;
  return 0;
}

static int combined_early_exit_walk(List value) {
  return early_exit_walk(value) + linear_second(value);
}
