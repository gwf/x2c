#include <assert.h>

int main(void) {
  String line = "  GET /docs/guide/values.html  ";

  // Slice, strip, split, and case-fold; the original is untouched.
  String request = line.strip(NULL);
  (String method, String path) = request.split(" ");
  assert(line.len() == 31 && method == "GET");

  // Interpolate values and expressions in place.
  String title = path.split("/").last().str().replace(".html", "");
  puts(%"$method $title ($(path.len()) bytes)");

  // A switch on a String selects its case by content.
  switch (method.lower()) {
    case "get":  puts("read it");  break;
    case "post": puts("write it"); break;
    default:     puts("refuse it");
  }

  // Join and repeat build text; equality is one pointer compare.
  String rule = "-".repeat(3) + " " + ", ".join(%("a" "b" "c"));
  assert(rule == "--- a, b, c");
  puts(rule);
  return 0;
}
