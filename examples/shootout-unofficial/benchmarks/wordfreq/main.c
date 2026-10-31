#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Entry {
  const char *word;
  size_t len;
  int count;
} Entry;

static int random_state = 42;

static int next_int(int maximum) {
  random_state = (random_state * 3877 + 29573) % 139968;
  return (int) ((int64_t) random_state * maximum / 139968);
}

static char *make_text(int word_count) {
  char *text = malloc((size_t) word_count * 9 + 1);
  if (!text) abort();
  size_t length = 0;
  for (int i = 0; i < word_count; i++) {
    int word_length = next_int(4) + next_int(3) + 3;
    for (int j = 0; j < word_length; j++)
      text[length++] = (char) ('a' + next_int(26));
    if (i + 1 < word_count) text[length++] = ' ';
  }
  text[length] = '\0';
  return text;
}

static uint64_t hash_word(const char *word, size_t len) {
  uint64_t hash = 1469598103934665603ULL;
  for (size_t i = 0; i < len; i++)
    hash = (hash ^ (unsigned char) word[i]) * 1099511628211ULL;
  return hash;
}

static void add_word(
  Entry *table, size_t table_size, const char *word, size_t len
) {
  size_t slot = hash_word(word, len) & (table_size - 1);
  while (table[slot].word) {
    if (table[slot].len == len &&
        !memcmp(table[slot].word, word, len)) {
      table[slot].count++;
      return;
    }
    slot = (slot + 1) & (table_size - 1);
  }
  table[slot] = (Entry) {word, len, 1};
}

static uint64_t count_words(const char *text, int word_count) {
  size_t table_size = 1;
  while (table_size < (size_t) word_count * 2) table_size *= 2;
  Entry *table = calloc(table_size, sizeof(*table));
  if (!table) abort();

  const char *start = text;
  for (const char *cursor = text;; cursor++) {
    if (*cursor && !isspace((unsigned char) *cursor)) continue;
    if (cursor != start)
      add_word(table, table_size, start, (size_t) (cursor - start));
    if (!*cursor) break;
    start = cursor + 1;
  }

  uint64_t checksum = 0;
  for (size_t i = 0; i < table_size; i++) {
    if (!table[i].word) continue;
    checksum++;
    checksum += table[i].len * (size_t) table[i].count;
  }
  free(table);
  return checksum;
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int word_count = atoi(argv[1]);
  char *text = make_text(word_count);
  uint64_t checksum = 0;
  for (int i = 0; i < atoi(argv[2]); i++)
    checksum = checksum * 33 + count_words(text, word_count);
  free(text);
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}
