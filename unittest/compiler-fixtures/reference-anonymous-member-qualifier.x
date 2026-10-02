#include "x2c.x"
typedef struct Value { int n; } Value;
typedef struct Holder { const struct { Value value; }; } Holder;
static void bump(Value &value) { value.n++; }
int main(void) {
  Holder h = {{ {3} }};
  bump(h.value);
  return 0;
}
