#include "x2c.x"

typedef struct Value { int n; } Value;
typedef struct Holder { delegate Value value; } Holder;
static void Value.bump(Value &v) { v.n++; }

int main(void) {
  const Holder holder = {{3}};
  holder.bump();
  return 0;
}
