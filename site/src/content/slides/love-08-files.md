---
slug: files
section: love
tab: files
title: Read a file in one breath.
---

```x2c
#include <stdlib.h>

~int main(int argc, char **argv) {
String path = argc > 1 ? argv[1]
                      : "examples/data/love-files/quantities.txt";

// Read the whole text file and close it in one expression.
String text = path.open("r").string_close();
printf("whole file (%d bytes):\n%s", text.len(), text);

// Or stream lines, keeping the close beside the open.
File input = path.open("r");
defer input.close();
long total = 0;

// Skip blank lines; each remaining row has three valid longs.
foreach (String line in input) {
  if (!line.strip(NULL)) continue;
  String (a, b, c) = line.words().iter().list();
  long x = atol(a), y = atol(b), z = atol(c);
  total += x + y + z;
}
printf("total: %ld\n", total);
~return 0;
~}
```

Read a whole file in one expression or stream it line by line. Either way,
nobody manages a buffer. `defer` keeps the close next to the open, where
you can see it.

`words()` splits a row, destructuring names the fields, and plain `atol`
finishes the job, because this is still C and C is allowed to help.
