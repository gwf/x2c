#include "x2c.x"

static void add(int &value, int amount) {
  value += amount;
}

static int exercise(int &value) {
  int captured = 0, inner = 0;

  macro Expression read() => value;
  macro Stmt assign(Expr $new_value) {
    value = $new_value;
  }
  macro Stmt update() {
    value++;
    value += 4;
  }
  macro Stmt forward(Expr $amount) {
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

  return captured == 100 && inner == 16 ? value : -1;
}

int main(void) {
  int value = 4;
  int result = exercise(value);
  printf("%d\n", result);
  return value != 4 || result != 4;
}
