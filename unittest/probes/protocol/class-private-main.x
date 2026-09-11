#include <assert.h>

Var private_number(void);
Var private_label(void);

int main(void) {
  Var number = private_number(), label = private_label();
  assert(number.tag() != label.tag());
  assert(number.repr() == %"Hidden { number: 7 }");
  assert(label.repr() == %"Hidden { label: \"two\" }");
  return 0;
}
