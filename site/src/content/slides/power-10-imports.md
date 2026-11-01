---
slug: imports
section: power
tab: imports
---

<!-- ignore: requires the separately built PCRE2 package -->
```x2c,ignore
~#include <assert.h>
// Import the package under a name you choose.
import "pcre2" as rx;

~int main(void) {
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

~int matches = 0;
foreach (String line in text.lines()) {
  rx.RegexpMatch found = request.match(line);
  if (found)
~  {
    puts(%"$(found[<method>]) requests $(found[<path>])");
~    matches++;
~  }
}
~assert(matches == 3);
~return 0;
~}
```

Build the PCRE2 package before running the
[complete example](https://github.com/gwf/x2c/blob/main/examples/power/imports.x).
`import ... as rx` gives the shipped PCRE2 package a local alias and
exposes its main type, `rx.Regexp`. `rx.Regexp.compile` builds the pattern;
`rx.Regexp.match` returns named captures. Indexing and ordinary control
flow use the results, while `auto` releases the
compiled pattern.
