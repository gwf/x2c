#include <assert.h>
#include <string.h>

int main(void) {
  // Compare text with ==, whether literal or built at runtime.
  String padded = "  hello  ", prefix = "hel";
  String word = padded.strip(), same = prefix + "lo";
  if (word == "hello" && word == same)
    puts("same text");

  // Transformations produce new values; the original stays untouched.
  String loud = word.upper();
  String first = word[:1];
  assert(padded == "  hello  " && word == "hello" && loud == "HELLO");

  // Interpolate text and expressions directly.
  puts(%"$first: $loud ($(word.len()) bytes)");

  // Read-only C functions accept nonempty Strings directly.
  printf("C sees %zu bytes\n", strlen(word));
  return 0;
}
