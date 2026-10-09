#include "component.x"

static Array tracked;
static int bases, keys, values;
static Array next_base(void) { bases++; return tracked; }
static int next_key(void) { keys++; return 0; }
static int next_value(void) { values++; return 2; }

int main(void) {
  Array items = [];
  items.push((uchar) 7);
  tracked = items;
  Var read = items[0];
  Var stored = (items[0] = (uchar) 8);
  Var updated = (next_base()[next_key()] += next_value());
  Var old = items[0]++;
  Var prefix = ++items[0];
  printf("access: %d %d %d %d %d %d %s\n",
    read.int(), stored.int(), updated.int(), old.int(), prefix.int(),
    items[0].int(), items[0].tag().str());
  printf("once: %d %d %d\n", bases, keys, values);
  if (bases != 1 || keys != 1 || values != 1 || items[0].int() != 12)
    return 1;

  int failed = 0;
  try { (void) (items[0] += 1e300); }
  catch %(conv-range *): { failed = 1; }
  printf("failed: %d retained: %d %s\n",
    failed, items[0].int(), items[0].tag().str());
  if (!failed || items[0].int() != 12) return 2;

  Map counts = {};
  Var inserted = (counts[<new>] += (uchar) 3);
  Var map_old = counts[<new>]++;
  printf("map: %d %d %d %s\n", inserted.int(), map_old.int(),
    counts[<new>].int(), counts[<new>].tag().str());
  if (inserted.int() != 3 || map_old.int() != 3 ||
      counts[<new>].int() != 4) return 3;
  int missing = 0;
  try { counts[<absent>] -= 1; }
  catch %(bad-arg *): { missing = 1; }
  printf("kernel missing: %d absent: %d\n", missing, counts[<absent>] is void);
  if (!missing || counts[<absent>] is not void) return 4;
  items.free();
  return 0;
}
