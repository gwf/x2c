#include "x2c.x"

int main(void) {
  Buffer buf = Buffer.new(0);
  buf.write("hey");
  char first = buf[0], last = buf[-1], missing = buf[9];
  printf("%c %c %d\n", first, last, missing);
  return 0;
}
