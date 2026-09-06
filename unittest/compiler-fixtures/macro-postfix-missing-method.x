#include "x2c.x"

typedef struct MacroMissingMethod {
  int value;
} MacroMissingMethod;

macro Expression $macro_call_missing(Expr $value) => (
  $value.missing()
)

int main(void) {
  MacroMissingMethod value = { .value = 1 };
  return $macro_call_missing(value);
}
