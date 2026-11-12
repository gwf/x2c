---
slug: imports
section: power
home: true
order: 7
tab: packages
title: Bring a library into the language.
---

<!-- ignore: requires the linked package. -->
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

Import PCRE2 under the name `rx`, compile a pattern, and read named captures. Package types and methods work alongside ordinary x2c Strings, iteration, and scoped cleanup.

[Full source](https://github.com/gwf/x2c/blob/main/examples/power/imports.x).
