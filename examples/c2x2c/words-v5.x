#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static Map file_unique_words(String filename) {
  String text = filename.open("r").string_close()
    .filter(%!(unsigned char c) => !ispunct(c)).lower();
  Map counts = {};
  foreach (String word in text.words())
    counts[word] += 1;
  return counts;
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  Map counts = file_unique_words(argv[1]);
  Array ranked = counts.enumerate()
    .map(%!(List entry) => entry.reverse()).array().sort();
  foreach (Var (count, word) in ranked[-10:])
    puts(%"$count\t$word");
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}
