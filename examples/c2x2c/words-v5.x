#include "substring-map.x"
#include <stdio.h>
#include <stdlib.h>

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static Map file_unique_words(String filename) {
  String text = filename.open("r").string_close()
    .reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in text)
    counts.increment(word);
  return counts.strings();
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  Map counts = file_unique_words(argv[1]);
  Array ranked = [];
  foreach (Var (word, count) in counts) {
    if (ranked.len() == 10 && count < ranked[0][0]) continue;
    ranked.heap_push(%($count $word));
    if (ranked.len() > 10) ranked.heap_pop();
  }
  foreach (List pair in ranked.sort()) {
    (int count, String word) = pair;
    puts(%"$count\t$word");
  }
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}
