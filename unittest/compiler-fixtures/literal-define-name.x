#include "x2c.x"

#define ROWS 64
#define SCALE(x) ((x) * 2)

int main(void) {
  List shape = %(ROWS 4);         // a bare macro name is a Symbol: warned
  List value = %(${(long) ROWS} 4);   // a typed unquote: 64
  List call = %(SCALE 4);         // a function-like macro is never data
  printf("%s %s %s\n", shape.repr(), value.repr(), call.repr());
  return 0;
}
