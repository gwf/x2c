typedef struct SnapshotValue { int count; } SnapshotValue;
typedef SnapshotValue SnapshotAlias;
typedef int (*SnapshotCallback)(SnapshotValue *);

typedef struct SnapshotHolder {
  SnapshotValue value;
  SnapshotValue *pointer;
  SnapshotCallback callback;
} SnapshotHolder;

int snapshot_global;

static int snapshot_helper(int value) => value + 1;

int snapshot_leaf(SnapshotValue *value) {
  value.count = snapshot_helper(value.count);
  return value.count;
}

int snapshot_middle(SnapshotValue *value) => snapshot_leaf(value);

int snapshot_entry(SnapshotValue *value) {
  int sum = snapshot_middle(value);
  for (int i = 0; i < 2; i++) sum += snapshot_leaf(value);
  return sum;
}

SnapshotAlias snapshot_signature(SnapshotAlias value) => value;

size_t snapshot_layout(void) => sizeof(SnapshotValue);

int snapshot_callback(SnapshotCallback callback, SnapshotValue *value) {
  return callback(value);
}

int snapshot_cycle_a(int count);
int snapshot_cycle_b(int count) => count ? snapshot_cycle_a(count - 1) : 0;
int snapshot_cycle_a(int count) => count ? snapshot_cycle_b(count - 1) : 0;
