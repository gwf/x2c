---
slug: strings
section: love
home: true
order: 2
tab: text
title: Text me, maybe.
---

```x2c
~#include <assert.h>
~#include <string.h>

~int main(void) {
  // Compare text with ==, whether literal or built at runtime.
  String padded = "  hello  ", prefix = "hel";
  String word = padded.strip(), same = prefix + "lo";
  if (word == "hello" && word == same)
    puts("same text");

  // Transformations produce new values; the original stays untouched.
  String loud = word.upper();
  String first = word[:1];
~  assert(padded == "  hello  " && word == "hello" && loud == "HELLO");

  // Interpolate text and expressions directly.
  puts(%"$first: $loud ($(word.len()) bytes)");

  // Read-only C functions accept nonempty Strings directly.
  printf("C sees %zu bytes\n", strlen(word));
~  return 0;
~}
```

Strings compare by contents with `==`, so literals and independently constructed values agree without `strcmp`. Strip whitespace, change case, and take slices without changing the original. Interpolation puts values and expressions directly into the result.

Strings interoperate with C functions that read their bytes. Empty Strings are `NULL`, so respect the C function's null-pointer contract. Strings are immutable; never pass one as a writable destination.
