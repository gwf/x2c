#include "x2c.x"

int main(void) {
  String text = %"hello";
  text[0] = 'j';
  return 0;
}
