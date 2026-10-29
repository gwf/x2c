---
title: Strings
group: Values
---

```x2c
~#include <assert.h>
~#include <string.h>
~int main(void) {
String s = "  Hello, World  ";
String t = s.strip(NULL);                  // immutable: every op is new
assert(t[:5] == "Hello" && t[-5:] == "World" && t.len() == 12);
(String a, String b) = t.split(", ");      // split, join, replace, lower
String u = %"$a and $(b.lower())!";        // interpolation
assert(u == "Hello and world!" && ", ".join(%("a" "b")) == "a, b");
foreach (char c in a) putchar(c);          // bytes; strlen(a) works too
switch (a) { case "Hello": puts(" hi"); break; default: puts(" ?"); }
long n;
assert("42".try_long(n) && n == 42 && strlen(t) == 12);
~return 0;
~}
```

- Equal content is one object, so `==` is a pointer compare and a
  `switch` can select by content.
- A nonempty String passes to read-only C functions as a `char *`.
- `words()`, `lines()`, `startswith()`, `contains()`, `repeat()`,
  `upper()`, `try_long()`, `try_double()`.
