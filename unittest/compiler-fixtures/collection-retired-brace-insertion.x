#include "x2c.x"

/* `${` inside a String is the retired insertion spelling. */
int main(void) {
  int n = 42;
  String text = %"n=${n}";
  return text.len();
}
