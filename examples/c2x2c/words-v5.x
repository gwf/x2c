/*  words-v5.x -- one file-counting function

    Consolidates V4's reading and counting into count_words. Keeps its
    MapSubInt result and Substr/int iteration, materializes only heap candidate
    words, and prints with interpolation.
*/

#include <stdio.h>
#include <stdlib.h>
#include "substring-map.x"

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  print_top_ten(count_words(argv[1]));
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void print_top_ten(MapSubInt counts) {
  Array ranked = [];
  foreach ((Substr word, int count) in counts) {
    if (ranked.len() == 10 && count < ranked[0][0]) continue;
    ranked.heap_push(%($count ${word.str()}));
    if (ranked.len() > 10) ranked.heap_pop();
  }
  foreach (List pair in ranked.sort()) {
    (int count, String word) = pair;
    puts(%"$count\t$word");
  }
}

static MapSubInt count_words(String filename) {
  String text = filename.open("r").string_close()
    .reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in text)
    counts.increment(word);
  return counts;
}
