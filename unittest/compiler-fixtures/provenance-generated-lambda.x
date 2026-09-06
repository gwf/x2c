#include "x2c.x"
static String text;

int main(void) {
  List values = %(1);
  values.map(%!(value) => value * text);
  return 0;
}
