#include "x2c.x"

typedef struct Plain {
  int value;
} *Plain;

Var Plain.var(Plain value) {
  return Var.new(<plain>, value);
}

Plain Var.plain(Var value) {
  return (Plain) value.pointer();
}

int main(void) {
  Plain value = Scope.malloc(sizeof(struct Plain));
  value.value = 1;
  Plain result = -value;
  return result.value;
}
