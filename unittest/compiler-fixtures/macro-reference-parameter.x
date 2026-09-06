static void add(int &value, int amount) {
  value += amount;
}

macro Unit $define_reference(Type $type) => {
  static void $(x2c.ident "macro_add")($type &value) {
    value += 5;
    add(value, 1);
  }
}

$define_reference(int);

int main(void) {
  int value = 3;
  macro_add(value);
  printf("%d\n", value);
  return 0;
}
