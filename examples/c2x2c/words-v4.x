#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void count_word(Map counts, String word) {
  counts[word] += 1; // Map owns lookup, insertion, and growth.
}

static void count_line(Map counts, String line) {
  line = line.filter(%!(unsigned char c) => !ispunct(c)).lower();
  foreach (String word in line.words())
    count_word(counts, word);
}

static void print_top_ten(Map counts) {
  Array ranked = counts.enumerate()
    .map(%!(List entry) => entry.reverse()).array().sort();
  foreach (Var (count, word) in ranked[-10:])
    printf("%s\t%s\n", count, word);
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  Map counts = {}; // Replaces Counts, buckets, chains, and manual allocation.
  File input = File.open(argv[1], "r"); // Open failures raise.
  defer input.close(); // Close on return.
  foreach (String line in input) // No getline.
    count_line(counts, line);
  print_top_ten(counts);
  return EXIT_SUCCESS; // Root scope reclaims the Map and ranking Array.
}
