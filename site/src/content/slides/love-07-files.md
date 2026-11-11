---
slug: files
section: love
home: true
order: 7
tab: files
title: Read the file. Use its contents.
---

```x2c
#include <stdlib.h>
~#include "path.x"

~int main(int argc, char **argv) {
String path = argc > 1 ? argv[1]
                      : example_data("love-files/quantities.txt");

// Read the whole text file and close it in one expression.
String text = path.open("r").string_close();
printf("whole file (%d bytes):\n%s", text.len(), text);

// Or stream lines, keeping the close beside the open.
auto File input = path.open("r");
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

~// The checked-in data sits beside the examples wherever they live.
~String example_data(String name) {
~  Path source = String.new(__FILE__);
~  return source.dirname().join("../data").join(name);
~}
```

Read a whole file as text or process its lines one at a time. File methods handle the buffers; ordinary String and collection operations handle the contents.
