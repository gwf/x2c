/* Frame-slot cursor walks preserve collection reads and loop exits. */
#include "x2c.x"

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
  while (values.try_next(&cursor, &item)) { }
  return cursor * 10 + (int) item;
}

meta int cursor_after_map(Map values) {
  unsigned cursor = 0;
  Var key = 0, value = 0;
  while (values.try_next(&cursor, &key, &value)) { }
  return (int) value;
}

meta int cursor_after_list(List values) {
  List cursor = values;
  Var item = 0;
  while (values.try_next(&cursor, &item)) { }
  return (int) item;
}

meta int cursor_address(Array values) {
  int total = 0;
  {
    int cursor = 0;
    Var item = 0;
    while (values.try_next(&cursor, &item)) {
      Var *output = &item;
      *output = 7;
      total += (int) item;
    }
  }
  return total;
}

int main(void) {
  Array values = [1, 2, 3, 4, 5], empty = [];
  Map weights = {1: 2, 3: 4};
  Array changing = [1, 2];
  printf("array %d %d\n", $(cursor_array (List.array '(1 2 3 4 5))),
         cursor_array(values));
  printf("empty %d %d\n", $(cursor_array (List.array '())),
         cursor_array(empty));
  printf("nested %d %d\n",
         $(cursor_nested (List.array '(1 2 3 4 5)) (Map_of '(1 2 3 4))),
         cursor_nested(values, weights));
  printf("mutate %d %d\n", $(cursor_mutate (List.array '(1 2))),
         cursor_mutate(changing));
  printf("snapshot %d\n", $(cursor_snapshot (Map_of '(1 2 3 4))));
  printf("after-array %d %d\n",
         $(cursor_after_array (List.array '(1 2 3 4 5))),
         cursor_after_array(values));
  printf("after-map %d\n", $(cursor_after_map (Map_of '(1 2 3 2))));
  printf("after-list %d %d\n", $(cursor_after_list '(1 2 3)),
         cursor_after_list(%(1 2 3)));
  printf("address %d %d\n", $(cursor_address (List.array '(1 2 3 4 5))),
         cursor_address(values));
  values.free();
  empty.free();
  weights.cleanup();
  changing.free();
  return 0;
}
