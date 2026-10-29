#include "x2c.x"

class Box struct { int n; } *;

int main(void) {
  Box box = Box.new(1);
  return box[0].n;
}
