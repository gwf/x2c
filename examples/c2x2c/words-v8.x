/*  words-v8.x -- a reusable word-frequency API

    V7 becomes Path.frequencies(), returning class Frequencies MapStringInt.
    The module releases intermediate storage before returning; main only
    handles arguments and prints the result. Earlier versions rely on root
    Scope and canonical-pool shutdown for their remaining allocations.
*/

#include "frequencies.x"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE_OR_DIR");
  Path root = argv[1];
  print_top_ten(root.frequencies());
  return EXIT_SUCCESS;
}

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void print_top_ten(MapStringInt counts) {
  Array ranked = [];
  foreach ((String word, int count) in counts) {
    if (ranked.len() == 10 && count < ranked[0][0]) continue;
    ranked.heap_push(%($count $word));
    if (ranked.len() > 10) ranked.heap_pop();
  }
  foreach ((int count, String word) in ranked.sort())
    puts(%"$count\t$word");
}
