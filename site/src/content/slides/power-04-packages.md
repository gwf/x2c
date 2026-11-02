---
slug: packages
section: power
tab: packages
title: One namespace, zero collisions.
---

<!-- ignore: requires the separately built PCRE2 package -->
```x2c,ignore
~#include <assert.h>
~
// Import the package under a name you choose.
import "pcre2" as rx;

int main(void) {
  // Compile a pattern with named captures; release it on exit.
  auto rx.Regexp request = rx.Regexp.compile(
    "^(?<method>[A-Z]+) (?<path>/[^ ]+)$", 0);

  // Sample requests include lines the pattern will ignore.
  List requests = %("GET /docs" "POST /build" "-- idle --"
                    "DELETE /cache" "GET missing-slash");
  ~int matches = 0;
  foreach (String line in requests) {
    rx.RegexpMatch found = request.match(line);
    if (!found) continue;
    puts(%"$(found[<method>]) requests $(found[<path>])");
    ~matches++;
  }
  ~assert(matches == 3);
  return 0;
}
```

Build the PCRE2 package before running the
[complete example](https://github.com/gwf/x2c/blob/main/examples/power/imports.x).

x2c has one flat namespace, like C, and packages keep names apart. A
package's public names carry its prefix, so two packages can both
export a `Regexp`. `import "pcre2" as rx` gives you a local alias and dotted
access to the package's types and methods.

Wrapped C libraries are packages too: PCRE2, SQLite, raylib, libcurl,
libuv, BLIS, torch. Build once, `import` by name, and the native API is
still available.
