/*  words-v0.c -- native C word-frequency baseline

    Reads one file, removes punctuation, lowercases words, and counts them in
    an explicit hash table. Sorts all entries to print the ten most frequent
    words, then frees the table and its copied word strings.
*/

#include <ctype.h>
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

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void *allocate(size_t count, size_t size) {
  void *memory = calloc(count, size);
  if (!memory)
    fail("Out of memory.");
  return memory;
}

static uint64_t hash_word(const char *word) {
  uint64_t hash = 0xcbf29ce484222325ULL;
  for (const unsigned char *p = (const unsigned char *)word; *p; ++p) {
    hash ^= *p;
    hash *= 0x100000001b3ULL;
  }
  return hash;
}

static void normalize_word(char *word) {
  char *out = word;
  for (unsigned char *p = (unsigned char *)word; *p; ++p)
    if (!ispunct(*p)) *out++ = (char)tolower(*p);
  *out = '\0';
}

static void grow_counts(Counts *counts) {
  if (counts->capacity > SIZE_MAX / 2)
    fail("Too many words.");
  size_t capacity = counts->capacity ? counts->capacity * 2 : 64;
  Entry **buckets = allocate(capacity, sizeof(*buckets));
  for (size_t i = 0; i < counts->capacity; ++i) {
    Entry *entry = counts->buckets[i];
    while (entry) {
      Entry *next = entry->next;
      size_t bucket = entry->hash % capacity;
      entry->next = buckets[bucket];
      buckets[bucket] = entry;
      entry = next;
    }
  }
  free(counts->buckets);
  counts->buckets = buckets;
  counts->capacity = capacity;
}

static void count_word(Counts *counts, const char *word) {
  if (!counts->capacity) grow_counts(counts);
  uint64_t hash = hash_word(word);
  size_t bucket = hash % counts->capacity;
  for (Entry *entry = counts->buckets[bucket]; entry; entry = entry->next) {
    if (entry->hash == hash && strcmp(entry->word, word) == 0) {
      ++entry->count;
      return;
    }
  }
  if (counts->length >= counts->capacity - counts->capacity / 4) {
    grow_counts(counts);
    bucket = hash % counts->capacity;
  }
  Entry *entry = allocate(1, sizeof(*entry));
  entry->word = strdup(word);
  if (!entry->word)
    fail("Out of memory.");
  entry->count = 1;
  entry->hash = hash;
  entry->next = counts->buckets[bucket];
  counts->buckets[bucket] = entry;
  ++counts->length;
}

static void count_line(Counts *counts, char *line) {
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

static int compare_entries(const void *a, const void *b) {
  const Entry *left = *(Entry *const *)a;
  const Entry *right = *(Entry *const *)b;
  if (left->count != right->count) return left->count > right->count ? -1 : 1;
  return strcmp(left->word, right->word);
}

static void print_top_ten(const Counts *counts) {
  if (!counts->length) return;
  Entry **entries = allocate(counts->length, sizeof(*entries));
  size_t length = 0;
  for (size_t i = 0; i < counts->capacity; ++i)
    for (Entry *entry = counts->buckets[i]; entry; entry = entry->next)
      entries[length++] = entry;
  qsort(entries, length, sizeof(*entries), compare_entries);
  for (size_t i = 0; i < length && i < 10; ++i)
    printf("%d\t%s\n", entries[i]->count, entries[i]->word);
  free(entries);
}

static void free_counts(Counts *counts) {
  for (size_t i = 0; i < counts->capacity; ++i) {
    Entry *entry = counts->buckets[i];
    while (entry) {
      Entry *next = entry->next;
      free(entry->word);
      free(entry);
      entry = next;
    }
  }
  free(counts->buckets);
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "Usage: %s FILE\n", argv[0]);
    return EXIT_FAILURE;
  }
  FILE *input = fopen(argv[1], "r");
  if (!input) {
    perror(argv[1]);
    return EXIT_FAILURE;
  }
  Counts counts = {0};
  char *line = NULL;
  size_t capacity = 0;
  while (getline(&line, &capacity, input) != -1) count_line(&counts, line);
  int finished = feof(input);
  free(line);
  fclose(input);
  if (!finished) {
    free_counts(&counts);
    fprintf(stderr, "Could not finish reading %s\n", argv[1]);
    return EXIT_FAILURE;
  }
  print_top_ten(&counts);
  free_counts(&counts);
  return EXIT_SUCCESS;
}
