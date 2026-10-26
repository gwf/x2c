/*  words-v4.x -- native typed counting map

    Replaces V3's explicit hash table with MapSubInt. Uses mixed-type foreach
    bindings to read Substr keys and int counts directly, while retaining
    borrowed word storage and the bounded top-ten heap.
*/

#include <stdio.h>
#include <stdlib.h>
#include "substring-map.x"

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  MapSubInt counts = MapSubInt.new(); // Replaces the explicit table.
  File input = File.open(argv[1], "r"); // Open failures raise.
  defer input.close(); // Close on return.
  count_words(counts, input.string());
  print_top_ten(counts);
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void count_words(MapSubInt counts, String text) {
  text = text.reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  foreach (Substr word in text)
    count_word(counts, word);
}

static void print_top_ten(MapSubInt counts) {
  Array ranked = [];
  foreach ((Substr word, int count) in counts) {
    if (ranked.len() == 10 && count < ranked[0][0]) continue;
    ranked.heap_push($(count, word.str()));
    if (ranked.len() > 10) ranked.heap_pop();
  }
  foreach ((int count, String word) in ranked.sort())
    printf("%d\t%s\n", count, word);
}

static void count_word(MapSubInt counts, Substr word) {
  counts.increment(word); // Map owns lookup, insertion, and growth.
}
