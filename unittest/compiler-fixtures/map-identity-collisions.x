static unsigned _collision(Var value) {
  (void) value;
  return 7;
}

static void _exercise(int maps) {
  Map table = %{};
  Array keys = %[];
  for (int i = 0; i < 40; i++) {
    Var key;
    if (maps) key = %{<value>: 1};
    else key = %[1];
    keys.push(key);
    table[key] = i;
  }
  int sum = 0;
  foreach (Var key, keys) sum += table[key].int();
  printf("%s equal=%d identical=%d entries=%u sum=%d\n",
         maps ? "map" : "array", keys[0] == keys[1],
         keys[0] === keys[1], table.len(), sum);
  table[keys[0]] = 100;
  printf("replacement=%d ", table[keys[0]].int());
  if (maps) {
    Map key = keys[0];
    key[<value>] = 2;
  }
  else {
    Array key = keys[0];
    key.push(2);
  }
  printf("mutated=%d removed=%d ", table[keys[0]].int(),
         table.del(keys[1]).int());
  sum = 0;
  for (int i = 0; i < 40; i++)
    if (i != 1) sum += table[keys[i]].int();
  printf("missing=%d remaining=%u sum=%d\n",
         table[keys[1]] is void, table.len(), sum);
}

int main(void) {
  VarMethods methods = { .hash = _collision };
  printf("registered=%d,%d\n",
         x2c_register_builtin_descriptor(<array>, methods),
         x2c_register_builtin_descriptor(<map>, methods));
  _exercise(0);
  _exercise(1);
  return 0;
}
