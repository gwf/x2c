typedef struct SnapshotValue { long unrelated; } SnapshotValue;
static int snapshot_helper(int value) => value - 1;
int snapshot_other(int value) => snapshot_helper(value);
