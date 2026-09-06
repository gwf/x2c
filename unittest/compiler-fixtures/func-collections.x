#include "x2c.x"

typedef Var (*UnaryFunction)(Var);

static Var increment(Var value) {
  return value + 1;
}

static int next_byte(char value) {
  return value + 1;
}

int main(void) {
  List values = %(1 2 3);
  List direct = values.map(increment);

  UnaryFunction pointer = increment;
  Array dynamic = %[4, 5].map(pointer);

  int bias = 2;
  List captured = values.map(%!(Var value) => value + bias);
  String text = %"ab".map(%!(char value) => value + bias);
  String mapped = %"ab".map(next_byte);

  printf("%s %s %s %s %s\n", direct.repr(), dynamic.repr(),
         captured.repr(), text, mapped);
  return 0;
}
