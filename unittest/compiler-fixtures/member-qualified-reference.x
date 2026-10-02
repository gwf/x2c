#include "x2c.x"

typedef struct Value { int n; } Value;
typedef volatile Value VolatileValue;
typedef struct Holder { Value value; Value *pointer; } Holder;
typedef const Holder ConstHolder;
typedef int Row[2];
typedef struct Rows { Row values; } Rows;

static int Value.read(const Value &v) => v.n;
static int Value.read_volatile(volatile Value &v) => v.n;
static int VolatileValue.read_alias(VolatileValue &v) => v.n;
static void Value.bump(Value &v) { v.n++; }
static void increment(int &value) { value++; }

int main(void) {
  Value value = {7};
  ConstHolder holder = {{3}, &value};
  ConstHolder *pointer = &holder;
  volatile Holder changing = {{5}, NULL};
  VolatileValue qualified = {4};
  const Rows rows = {{10, 11}};
  (*holder.pointer).bump();
  void (*step)(int &value) = increment;
  step(value.n);
  printf("%d %d %d %d %d %d\n", holder.value.read(),
    pointer->value.read(), changing.value.read_volatile(),
    qualified.read_alias(), value.n, rows.values[0]);
  return 0;
}
