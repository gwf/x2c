#include <assert.h>
#include <string.h>

int main(void) {
// Transform and slice values; keep the original input.
String raw = "  tea:42  ", row = raw.strip(NULL);
String name = row[:3].upper(), title = name + " ORDER";

// Equal contents compare in constant time, however they were built.
assert(title == %"tea order".upper());

// Parse a sliced field and interpolate the result.
long quantity;
if (row[4:].try_long(&quantity))
  puts(%"$title: ${quantity + 1}");

// Iterate bytes directly, or use ordinary C string functions.
assert(strcmp(raw, "  tea:42  ") == 0);
foreach (char ch, name)
  putchar(ch);
printf(" has %zu letters; original: [%s]\n", strlen(name), raw);
return 0;
}
