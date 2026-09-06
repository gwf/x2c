/*  imports.x -- consume a package through `import`.

    The alias is resolution-only: `g.Greeting` compiles to the package's own
    `greet__Greeting`, so two packages may both publish a `Greeting`.
*/

import "greet" as g;

#include <stdio.h>

int main(void) {
  g.Greeting greeting = g.Greeting.new(%"x2c");
  for (int line = 0; line < 3; line++) printf("%s", %"${greeting.line()}\n");
  printf("%s", %"${g.repeat(%"ping", 3)}\n");
  return 0;
}
