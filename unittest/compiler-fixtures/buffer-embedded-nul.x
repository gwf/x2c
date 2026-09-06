#include "x2c.x"

int main(void) {
  char text[] = {'a', 0, 'b'};
  Buffer buf = Buffer.new(0);
  buf.write_len(text, sizeof(text));
  return 0;
}
