#include "x2c.x"

// A Declaration macro defined in the unit adds Strings in its initializer
// with the String protocol, as an imported one does.
macro Declaration $joined(Name $n) { String $n = "ij" + "kl"; }

$joined(joined);

int main(void) {
  printf("%s\n", joined);
  return 0;
}
