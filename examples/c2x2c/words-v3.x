#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Entry {
  String word; // Canonical String; no per-word copy.
  int count;
  uint64_t hash;
  struct Entry *next;
} Entry;

typedef struct {
  Entry **buckets;
  size_t capacity;
  size_t length;
} Counts;

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void grow_counts(Counts *counts) {
  if (counts.capacity > SIZE_MAX / 2)
    fail("Too many words.");
  size_t capacity = counts.capacity ? counts.capacity * 2 : 64;
  Entry **buckets = xcalloc(capacity, sizeof(*buckets)); // Replaces allocate.
  for (size_t i = 0; i < counts.capacity; ++i) {
    Entry *entry = counts.buckets[i];
    while (entry) {
      Entry *next = entry.next;
      size_t bucket = entry.hash % capacity;
      entry.next = buckets[bucket];
      buckets[bucket] = entry;
      entry = next;
    }
  }
  xfree(counts.buckets); // Release obsolete scope-owned storage early.
  counts.buckets = buckets;
  counts.capacity = capacity;
}

static void count_word(Counts *counts, String word) {
  if (!counts.capacity) grow_counts(counts);
  uint64_t hash = word.hash(); // Cached hash replaces hash_word().
  size_t bucket = hash % counts.capacity;
  for (Entry *entry = counts.buckets[bucket]; entry; entry = entry.next) {
    if (entry.hash == hash && entry.word == word) { // Canonical equality.
      ++entry.count;
      return;
    }
  }
  if (counts.length >= counts.capacity - counts.capacity / 4) {
    grow_counts(counts);
    bucket = hash % counts.capacity;
  }
  Entry *entry = xcalloc(1, sizeof(*entry)); // Allocation failure raises.
  entry.word = word; // Keep the canonical String; no xmemdup.
  entry.count = 1;
  entry.hash = hash;
  entry.next = counts.buckets[bucket];
  counts.buckets[bucket] = entry;
  ++counts.length;
}

static void count_line(Counts *counts, String line) {
  line = line.filter(%!(unsigned char c) => !ispunct(c)).lower();
  foreach (String word in line.words())
    count_word(counts, word);
}

static void print_top_ten(const Counts *counts) {
  Array ranked = []; // (count word) tuples replace the sorting buffer.
  for (size_t i = 0; i < counts.capacity; ++i)
    for (Entry *entry = counts.buckets[i]; entry; entry = entry.next)
      ranked.push(%(${entry.count} ${entry.word}));
  foreach (Var (count, word) in ranked.sort()[-10:])
    printf("%s\t%s\n", count, word);
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  Counts counts = {0};
  File input = File.open(argv[1], "r"); // Open failures raise.
  defer input.close(); // Close on return.
  foreach (String line in input) // No getline.
    count_line(&counts, line);
  print_top_ten(&counts);
  return EXIT_SUCCESS; // Root scope frees entries and table.
}
