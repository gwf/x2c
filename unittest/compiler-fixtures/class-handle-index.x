#include "x2c.x"

class Box struct { int n; } *;

int main(void) {
  Box box = Box.new();
  return box[0].n;
}
