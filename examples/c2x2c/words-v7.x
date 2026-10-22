/*  words-v7.x -- parallel recursive directory counting

    Replaces V6's sequential map with four persistent workers. The caller
    accumulates each returned MapSubInt while its worker waits, then releases
    the table. Counting, accumulation, and ranking otherwise match V6.
*/

#include "substring-map.x"
#include "typed-map.x"
#include "path.x"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " DIR");
  print_top_ten(dir_unique_words(argv[1]));
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
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

static MapStringInt dir_unique_words(Path root) {
  if (!root.is_dir())
    fail("Not a directory: " + root);
  return root.walk().filter(Path.is_file).parallel_map(count_words, 4)
    .foldl(MapStringInt.new(), accumulate);
}

static Var count_words(Var filename) {
  String text = filename.string().open("r").string_close()
    .reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in text)
    counts.increment(word);
  return counts;
}

static MapStringInt accumulate(MapStringInt total, MapSubInt counts) {
  foreach ((Substr word, int count) in counts) total.add_substr(word, count);
  counts.cleanup();
  return total;
}
