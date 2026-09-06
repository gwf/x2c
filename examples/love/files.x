#include <stdlib.h>

int main(void) {
String path = "quantities.txt";

// Read the whole text file and close it in one expression.
String text = path.open("r").string_close();
printf("whole file (%d bytes):\n%s", text.len(), text);

// Or stream lines, keeping the close beside the open.
File input = path.open("r");
defer input.close();
long total = 0;

// Skip blank lines; each remaining row has three valid longs.
foreach (String line, input) {
  if (!line.strip(NULL)) continue;
  String (a, b, c) = line.words().iter().list();
  long x = atol(a), y = atol(b), z = atol(c);
  total += x + y + z;
}
printf("total: %ld\n", total);
return 0;
}
