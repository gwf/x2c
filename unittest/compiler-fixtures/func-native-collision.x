#include "x2c.x"

extern long _is_list_literal(long value);

int main(void) {
  Func target = Func.new(_is_list_literal, %((func ((long))) long));
  return !target;
}
