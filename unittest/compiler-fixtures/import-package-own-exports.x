// A package import installs the exports of the package's own sources. A
// consumer file under the package directory, such as a test, delivers
// its export only at its own include.
#include "x2c.x"
import "tally";

int six = $tally.six();
int early = $own.value();
#include "packages/tally/tests/own.x"
