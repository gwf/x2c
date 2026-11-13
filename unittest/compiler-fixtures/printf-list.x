#include "x2c.x"

int main(void) {
  List items = %(1 2);
  Stdout.printf("list: %s\n", items);
  return 0;
}
