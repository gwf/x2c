/*  imports.x -- extract named request fields with the PCRE2 package

    In a checkout, `make -C packages/pcre2 run` builds the package and runs
    this example. With an installed x2c, run `x2c install pcre2` first; then
    `x2c run -q examples/power/imports.x` finds the package.
*/

#include <assert.h>
// Import the package under a name you choose.
import "pcre2" as rx;

int main(void) {
// Compile a pattern with named captures; release it on exit.
auto rx.Regexp request = rx.Regexp.compile(
  "^(?<method>[A-Z]+) (?<path>/[^ ]+)$", 0);

// Sample requests include lines the pattern will ignore.
String text = %"\
GET /docs
POST /build
-- idle --
DELETE /cache
GET missing-slash
";

int matches = 0;
foreach (String line in text.lines()) {
  rx.RegexpMatch found = request.match(line);
  if (found)
  {
    puts(%"$(found[<method>]) requests $(found[<path>])");
    matches++;
  }
}
assert(matches == 3);
return 0;
}
