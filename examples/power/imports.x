#include <assert.h>
// Import the package under a name you choose.
import "pcre2" as rx;

int main(void) {
// Compile a pattern with named captures; release it on exit.
rx.Regexp request = rx.Regexp.compile(
  "^(?<method>[A-Z]+) (?<path>/[^ ]+)$", 0);
defer request.free();

// Sample requests include lines the pattern will ignore.
List lines = %(
  "GET /docs"
  "POST /build"
  "-- idle --"
  "DELETE /cache"
  "GET missing-slash"
);

int matches = 0;
foreach (String line, lines) {
  rx.RegexpMatch found = request.match(line);
  if (found)
  {
    puts(%"${found[<method>]} requests ${found[<path>]}");
    matches++;
  }
}
assert(matches == 3);
return 0;
}
