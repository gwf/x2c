#include "path.x"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static Map word_count(String filename) {
  String text = filename.open("r").string_close()
    .filter(%!(unsigned char c) => !ispunct(c)).lower();
  Map counts = {};
  foreach (String word in text.words())
    counts[word] += 1;
  return counts;
}

static Map directory_count(Path root) {
  if (!root.is_dir())
    fail("Not a directory: " + root);
  return root.walk().filter(Path.is_file).map(word_count)
    .foldl({}, %!(Map counts, Map part) => counts.merge_with(part,
      %!(int a, int b) => a + b));
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " DIR");
  Map counts = directory_count(argv[1]);
  Array ranked = counts.enumerate()
    .map(%!(List x) => x.reverse()).array().sort();
  foreach (Var (count, word) in ranked[-10:])
    puts(%"$count\t$word");
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}
