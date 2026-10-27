/*  words-v1.x -- scope-owned allocation and deferred cleanup

    Keeps V0's line reader, hash table, and full sort. Replaces checked native
    allocations with scope-owned storage, borrows Counts through references,
    uses dot member access, and defers cleanup of the native getline buffer.
*/

#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Entry {
  char *word;
  int count;
  uint64_t hash;
  struct Entry *next;
} Entry;

typedef struct {
  Entry **buckets;
  size_t capacity;
  size_t length;
} Counts;

int main(int argc, char **argv) {
  if (argc != 2)
    fail("Usage: " + argv[0] + " FILE");
  FILE *input = fopen(argv[1], "r");
  if (!input) {
    String reason = String.new(strerror(errno));
    fail(argv[1] + ": " + reason);
  }
  Counts counts = {0}; // Default root scope needs no retain/release here.
  char *line = NULL;
  defer free(line); // x2c: replaces later free; getline uses native storage.
  size_t capacity = 0;
  while (getline(&line, &capacity, input) != -1) count_line(counts, line);
  int finished = feof(input);
  fclose(input);
  if (!finished)
    fail("Could not finish reading " + argv[1]);
  print_top_ten(counts);
  return EXIT_SUCCESS; // Root scope frees words and table.
}

static void count_line(Counts &counts, char *line) {
  char *p = line;
  while (*p) {
    while (isspace((unsigned char)*p)) ++p;
    if (!*p) break;
    char *word = p;
    while (*p && !isspace((unsigned char)*p)) ++p;
    if (*p) *p++ = '\0';
    normalize_word(word);
    if (*word) count_word(counts, word);
  }
}

static void print_top_ten(const Counts &counts) {
  if (!counts.length) return;
  Entry **entries = xcalloc(counts.length, sizeof(*entries)); // Scope-owned.
  size_t length = 0;
  for (size_t i = 0; i < counts.capacity; ++i)
    for (Entry *entry = counts.buckets[i]; entry; entry = entry.next)
      entries[length++] = entry;
  qsort(entries, length, sizeof(*entries), compare_entries);
  for (size_t i = 0; i < length && i < 10; ++i)
    printf("%d\t%s\n", entries[i].count, entries[i].word);
} // Removed free(entries): root scope releases the sorting array.

static void normalize_word(char *word) {
  char *out = word;
  for (unsigned char *p = (unsigned char *)word; *p; ++p)
    if (!ispunct(*p)) *out++ = (char)tolower(*p);
  *out = '\0';
}

static void count_word(Counts &counts, const char *word) {
  if (!counts.capacity) grow_counts(counts);
  uint64_t hash = hash_word(word);
  size_t bucket = hash % counts.capacity;
  for (Entry *entry = counts.buckets[bucket]; entry; entry = entry.next) {
    if (entry.hash == hash && strcmp(entry.word, word) == 0) {
      ++entry.count;
      return;
    }
  }
  if (counts.length >= counts.capacity - counts.capacity / 4) {
    grow_counts(counts);
    bucket = hash % counts.capacity;
  }
  Entry *entry = xcalloc(1, sizeof(*entry)); // x2c: allocation failure raises.
  entry.word = xmemdup(word, strlen(word) + 1); // Replaces strdup and check.
  entry.count = 1;
  entry.hash = hash;
  entry.next = counts.buckets[bucket];
  counts.buckets[bucket] = entry;
  ++counts.length;
}

static int compare_entries(const void *a, const void *b) {
  const Entry *left = *(Entry *const *)a;
  const Entry *right = *(Entry *const *)b;
  if (left.count != right.count) return left.count > right.count ? -1 : 1;
  return strcmp(left.word, right.word);
}

static void grow_counts(Counts &counts) {
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
  xfree(counts.buckets); // x2c: release obsolete scope-owned storage early.
  counts.buckets = buckets;
  counts.capacity = capacity;
}

static uint64_t hash_word(const char *word) {
  uint64_t hash = 0xcbf29ce484222325ULL;
  for (const unsigned char *p = (const unsigned char *)word; *p; ++p) {
    hash ^= *p;
    hash *= 0x100000001b3ULL;
  }
  return hash;
}

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}
