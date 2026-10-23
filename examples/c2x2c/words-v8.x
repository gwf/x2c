/*  words-v8.x -- a reusable word-frequency API

    V7 becomes Path.frequencies() and Frequencies.top(k). The Frequencies
    class wraps MapStringInt; ranking returns a sorted List.
    The module releases intermediate storage before returning; main only
    handles arguments, errors, and output. Earlier versions rely on root
    Scope and canonical-pool shutdown for their remaining allocations.
*/

#include "frequencies.x"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE_OR_DIR");
  Path root = argv[1];
  try foreach ((int count, String word) in root.frequencies().top(10))
    puts(%"$count\t$word");
  catch %(?code *detail): fail(cons(code, detail).repr());
  return EXIT_SUCCESS;
}

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}
