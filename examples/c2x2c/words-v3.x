/*  words-v3.x -- bounded top-ten heap

    Keeps V2's word counting but replaces the full sorting array and comparator
    with an Array min-heap of at most ten (count word) Lists. Destructures the
    final tuples for printing in ascending count and word order.
*/

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "substring.x"

typedef struct Entry {
  Substr word; // Borrows normalized text storage; no per-word copy.
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

static void count_word(Counts *counts, Substr word) {
  if (!counts.capacity) grow_counts(counts);
  uint64_t hash = word.hash();
  size_t bucket = hash % counts.capacity;
  for (Entry *entry = counts.buckets[bucket]; entry; entry = entry.next) {
    if (entry.hash == hash && entry.word.equal(word)) {
      ++entry.count;
      return;
    }
  }
  if (counts.length >= counts.capacity - counts.capacity / 4) {
    grow_counts(counts);
    bucket = hash % counts.capacity;
  }
  Entry *entry = xcalloc(1, sizeof(*entry)); // Allocation failure raises.
  entry.word = word;
  entry.count = 1;
  entry.hash = hash;
  entry.next = counts.buckets[bucket];
  counts.buckets[bucket] = entry;
  ++counts.length;
}

static void count_words(Counts *counts, String text) {
  text = text.reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  foreach (Substr word in text)
    count_word(counts, word);
}

static void print_top_ten(const Counts *counts) {
  Array ranked = []; // Keep only the ten largest (count word) tuples.
  for (size_t i = 0; i < counts.capacity; ++i)
    for (Entry *entry = counts.buckets[i]; entry; entry = entry.next) {
      if (ranked.len() == 10 && entry.count < ranked[0][0]) continue;
      ranked.heap_push(%(${entry.count} ${entry.word.str()}));
      if (ranked.len() > 10) ranked.heap_pop();
    }
  foreach (List pair in ranked.sort()) {
    (int count, String word) = pair;
    printf("%d\t%s\n", count, word);
  }
}

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  Counts counts = {0};
  File input = File.open(argv[1], "r"); // Open failures raise.
  defer input.close(); // Close on return.
  count_words(&counts, input.string());
  print_top_ten(&counts);
  return EXIT_SUCCESS; // Root scope frees entries and table.
}
