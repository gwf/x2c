#include "x2c.x"

meta void borrow(int **out, int *value) { *out = value; }

meta void parameter_store(int **out) {
  int value = 1;
  borrow(out, &value);
}

meta void unknown_store(void) {
  int value = 1;
  int **out = malloc(sizeof(int *));
  *out = &value;
}

int main(void) { return 0; }
