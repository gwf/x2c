/*  alias-included.x -- aliases across an include

    A public file-scope alias reaches the including file at the include
    line, with the file-scope binding its expression had where it was
    declared, even where a local of the same spelling hides that name. A
    `static` alias stays in its declaring file, so this file may declare
    its name.
*/

#include "x2c.x"
#include "alias-included/shared.x"

Config config = { 7 };

int main(void) {
  int config = 3;
  int private_level = 5;
  level = level + 1;
  printf("%d %d %d %d\n", level, doubled, config, private_level);
  return 0;
}
