/*  greet-client.x -- consume a package through `import`.

    The alias is resolution-only: `g.Greeting` compiles to the package's own
    `greet__Greeting`, so two packages may both publish a `Greeting`.

    Build the package, then run the example from the checkout root:

      make -C examples/packages/greet build
      x2c run -q --package-dir examples/packages examples/power/greet-client.x
*/

import "greet" as g;

int main(void) {
  g.Greeting greeting = g.Greeting.new(%"x2c");
  for (int line = 0; line < 3; line++) printf("%s", %"$(greeting.line())\n");
  printf("%s", %"$(g.repeat(%"ping", 3))\n");
  return 0;
}
