/* Frame-slot cursor walks preserve collection reads and loop exits. */
#include "x2c.x"

/* A Map from alternating keys and values. */
meta static Map cursor_map(List flat) {
  Array items = flat;
  Map map = {};
  for (int i = 0; i + 1 < items.len(); i += 2) map[items[i]] = items[i + 1];
  return map;
}

meta int cursor_array(Array values) {
  int total = 0;
  foreach (Var value, values) {
    if (value == 2) continue;
    if (value == 4) break;
    total = total * 10 + (int) value;
  }
  return total;
}

meta int cursor_nested(Array values, Map weights) {
  int total = 0;
  foreach (Var value, values)
    foreach (Var (key, weight), weights)
      total += (int) value * ((int) key + (int) weight);
  return total;
}

/* The cursor sees growth and each element is captured before the body
   changes the Array. */
meta int cursor_mutate(Array values) {
  int total = 0, index = 0;
  foreach (Var value, values) {
    if (index == 0) values.push(3);
    values[0] = 9;
    total = total * 10 + (int) value;
    index++;
  }
  return total;
}

/* The compile-time Map cursor keeps the snapshot it made on entry. */
meta int cursor_snapshot(Map values) {
  int total = 0;
  foreach (Var (key, value), values) {
    values[key] = 100;
    total += (int) value;
  }
  return total;
}

meta int cursor_after_array(Array values) {
  int cursor = 0;
  Var item = 0;
  while (values.try_next(cursor, item)) { }
  return cursor * 10 + (int) item;
}

meta int cursor_after_map(Map values) {
  unsigned cursor = 0;
  Var key = 0, value = 0;
  while (values.try_next(cursor, key, value)) { }
  return (int) value;
}

meta int cursor_after_list(List values) {
  List cursor = values;
  Var item = 0;
  while (values.try_next(cursor, item)) { }
  return (int) item;
}

meta int cursor_address(Array values) {
  int total = 0;
  {
    int cursor = 0;
    Var item = 0;
    while (values.try_next(cursor, item)) {
      Var *output = &item;
      *output = 7;
      total += (int) item;
    }
  }
  return total;
}

/* A `$` call passes Lists; these build the Array or Map each walk reads. */
meta static int array_walk(List items) => cursor_array(items);
meta static int nested_walk(List items, List flat) =>
  cursor_nested(items, cursor_map(flat));
meta static int mutate_walk(List items) => cursor_mutate(items);
meta static int snapshot_walk(List flat) => cursor_snapshot(cursor_map(flat));
meta static int after_array_walk(List items) => cursor_after_array(items);
meta static int after_map_walk(List flat) => cursor_after_map(cursor_map(flat));
meta static int address_walk(List items) => cursor_address(items);

int main(void) {
  Array values = [1, 2, 3, 4, 5], empty = [];
  Map weights = {1: 2, 3: 4};
  Array changing = [1, 2];
  printf("array %d %d\n", $array_walk(%(1 2 3 4 5)), cursor_array(values));
  printf("empty %d %d\n", $array_walk(%()), cursor_array(empty));
  printf("nested %d %d\n", $nested_walk(%(1 2 3 4 5), %(1 2 3 4)),
         cursor_nested(values, weights));
  printf("mutate %d %d\n", $mutate_walk(%(1 2)), cursor_mutate(changing));
  printf("snapshot %d\n", $snapshot_walk(%(1 2 3 4)));
  printf("after-array %d %d\n", $after_array_walk(%(1 2 3 4 5)),
         cursor_after_array(values));
  printf("after-map %d\n", $after_map_walk(%(1 2 3 2)));
  printf("after-list %d %d\n", $cursor_after_list(%(1 2 3)),
         cursor_after_list(%(1 2 3)));
  printf("address %d %d\n", $address_walk(%(1 2 3 4 5)),
         cursor_address(values));
  values.free();
  empty.free();
  weights.cleanup();
  changing.free();
  return 0;
}
