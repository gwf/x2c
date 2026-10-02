#include "x2c.x"

typedef struct Value { int n; } *Value;
Var Value.var(Value value) => Var.new(<value>, value);
Value Var.value(Var value) => (Value) value.pointer();
Value Value.add(Value left, Value right) => left;
protocol Var(Value);

int main(void) {
  Value value = NULL;
  value++;
  return 0;
}
