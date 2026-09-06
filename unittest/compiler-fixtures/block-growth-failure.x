#include "x2c.x"
#include <stdint.h>

int main(void) {
  Block block = Block.new(sizeof(char));
  block.append(NULL, SIZE_MAX);
  return 0;
}
