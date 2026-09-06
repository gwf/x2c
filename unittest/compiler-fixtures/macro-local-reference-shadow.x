#include "x2c.x"

static void add(int &value, int amount) {
  value += amount;
}

static int exercise(int &value) {
  int captured = 0, inner = 0;

  macro Expression read() => (value)
  macro Statement assign(Expr $new_value) => {
    value = $new_value;
  }
  macro Statement update() => {
    value++;
    value += 4;
  }
  macro Statement forward(Expr $amount) => {
    add(value, $amount);
  }

  {
    int value = 100;
    captured = read();
    assign(8);
    update();
    forward(3);
    inner = value;
  }

  return captured == 4 && inner == 100 ? value : -1;
}

int main(void) {
  int value = 4;
  int result = exercise(value);
  printf("%d\n", result);
  return value != 16 || result != 16;
}
