/* A managed initializer cannot manage a local that an earlier `$auto`
   already manages; the value would be released twice. */

#include "x2c.x"

int main(void) {
  Block a = $auto(Block.new(64));
  Block b = $auto((a));
  return b == a;
}
