#include "x2c.x"

typedef struct Value { int n; } Value;
typedef volatile Value VolatileValue;
typedef struct Holder { Value value; Value *pointer; } Holder;
typedef const Holder ConstHolder;
typedef int Row[2];
typedef struct Rows { Row values; } Rows;
typedef Row Grid[2];
typedef struct Pointers { int *values[1]; int *direct; } Pointers;
typedef struct Wrapped {
  const struct { Value promoted; Row row; int *pointer; };
} Wrapped;

static int Value.read(const Value &v) => v.n;
static int Value.read_volatile(volatile Value &v) => v.n;
static int VolatileValue.read_alias(VolatileValue &v) => v.n;
static void Value.bump(Value &v) { v.n++; }
static void increment(int &value) { value++; }
static int _read(const int &value) => value;

int main(void) {
  Value value = {7};
  ConstHolder holder = {{3}, &value};
  ConstHolder *pointer = &holder;
  volatile Holder changing = {{5}, NULL};
  VolatileValue qualified = {4};
  const Rows rows = {{10, 11}};
  const Grid grid = {{20, 21}, {22, 23}};
  const Pointers pointers = {{&value.n}, &value.n};
  Wrapped wrapped = {{{6}, {30, 31}, &value.n}};
  (*holder.pointer).bump();
  void (*step)(int &value) = increment;
  step(value.n);
  increment(*pointers.values[0]);
  increment(pointers.direct[0]);
  increment(*wrapped.pointer);
  printf("%d %d %d %d %d %d\n", holder.value.read(),
    pointer->value.read(), changing.value.read_volatile(),
    qualified.read_alias(), value.n, rows.values[0]);
  printf("%d %d %d\n", _read(grid[1][0]), _read(wrapped.row[1]),
    wrapped.promoted.read());
  return 0;
}
