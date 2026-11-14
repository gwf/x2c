#include <stdlib.h>
#include "path.x"

// The checked-in data sits beside the examples wherever they live.
String example_data(String name) {
  Path source = String.new(__FILE__);
  return source.dirname().join("../data", name);
}

int main(int argc, char **argv) {
  String path = argc > 1 ? argv[1]
                        : example_data("love-files/quantities.txt");

  // Read the whole text file and close it in one expression.
  String text = path.open("r").string_close();
  printf("whole file (%d bytes):\n%s", text.len(), text);

  // Or stream lines, keeping the close beside the open.
  auto File input = path.open("r");
  long total = 0;

  foreach (String line in input)
    foreach (String word in line.words())
      total += atol(word);
  printf("total: %ld\n", total);
  return 0;
}
