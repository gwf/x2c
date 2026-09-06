/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/wordfreq-ported ported.x
 *   /tmp/wordfreq-ported 50000 10
 */

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *word; size_t len; int count; } Entry;

static int _random_state = 42;

static int _next_int(int maximum) {
  _random_state = (_random_state * 3877 + 29573) % 139968;
  return (int) ((int64_t) _random_state * maximum / 139968);
}

static char *_make_text(int word_count) {
  char *text = Scope.malloc((size_t) word_count * 9 + 1);
  size_t length = 0;
  for (int i = 0; i < word_count; i++) {
    int word_length = _next_int(4) + _next_int(3) + 3;
    for (int j = 0; j < word_length; j++)
      text[length++] = (char) ('a' + _next_int(26));
    if (i + 1 < word_count) text[length++] = ' ';
  }
  text[length] = '\0';
  return text;
}

/* FNV-1a and the linear probe, folded into one function: the C splits them
   only because the hash needed a name to be called twice. */
static void _add_word(
  Entry *table, size_t mask, const char *word, size_t len) {
  uint64_t hash = 1469598103934665603ULL;
  for (size_t i = 0; i < len; i++)
    hash = (hash ^ (unsigned char) word[i]) * 1099511628211ULL;
  for (size_t slot = hash & mask; ; slot = (slot + 1) & mask) {
    if (!table[slot].word) {
      table[slot].word = word;
      table[slot].len = len;
      table[slot].count = 1;
      return;
    }
    if (table[slot].len == len && !memcmp(table[slot].word, word, len)) {
      table[slot].count++;
      return;
    }
  }
}

static uint64_t _count_words(const char *text, int word_count) {
  Scope.retain();
  size_t size = 1;
  while (size < (size_t) word_count * 2) size *= 2;
  Entry *table = Scope.calloc(size, sizeof(Entry));

  const char *start = text;
  for (const char *cursor = text;; cursor++) {
    if (*cursor && !isspace((unsigned char) *cursor)) continue;
    if (cursor != start)
      _add_word(table, size - 1, start, (size_t) (cursor - start));
    if (!*cursor) break;
    start = cursor + 1;
  }

  uint64_t checksum = 0;
  for (size_t i = 0; i < size; i++)
    if (table[i].word) checksum += 1 + table[i].len * (size_t) table[i].count;
  Scope.release();
  return checksum;
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int word_count = atoi(argv[1]), runs = atoi(argv[2]);
  const char *text = _make_text(word_count);
  uint64_t checksum = 0;
  for (int i = 0; i < runs; i++)
    checksum = checksum * 33 + _count_words(text, word_count);
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}
