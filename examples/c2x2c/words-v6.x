/*  words-v6.x -- sequential recursive directory counting

    Extends V5 to every normal file under a directory. Returns each file's
    MapSubInt directly and folds it into one MapStringInt, converting a view
    to String only when inserting a new word into the total.
*/

#include "substring-map.x"
#include "typed-map.x"
#include "path.x"
#include <stdio.h>
#include <stdlib.h>

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
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

static MapStringInt dir_unique_words(Path root) {
  if (!root.is_dir())
    fail("Not a directory: " + root);
  return root.walk().filter(Path.is_file).map(count_words)
    .foldl(MapStringInt.new(), accumulate);
}

static void print_top_ten(MapStringInt counts) {
  Array ranked = [];
  foreach ((String word, int count) in counts) {
    if (ranked.len() == 10 && count < ranked[0][0]) continue;
    ranked.heap_push(%($count $word));
    if (ranked.len() > 10) ranked.heap_pop();
  }
  foreach (List pair in ranked.sort()) {
    (int count, String word) = pair;
    puts(%"$count\t$word");
  }
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " DIR");
  print_top_ten(dir_unique_words(argv[1]));
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}
