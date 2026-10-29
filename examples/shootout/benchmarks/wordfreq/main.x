/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/wordfreq-idiomatic main.x
 *   /tmp/wordfreq-idiomatic 50000 10
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "substring-map.x"

static int _random_state = 42;

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int word_count = atoi(argv[1]);
  String text = _make_text(word_count);
  uint64_t checksum = 0;
  for (int i = 0; i < atoi(argv[2]); i++)
    checksum = checksum * 33 + _count(text, word_count);
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}

static String _make_text(int word_count) {
  String text = String.malloc(word_count * 9 + 1);
  char *bytes = text;
  int length = 0;
  for (int i = 0; i < word_count; i++) {
    int word_length = _next_int(4) + _next_int(3) + 3;
    for (int j = 0; j < word_length; j++)
      bytes[length++] = 'a' + _next_int(26);
    if (i + 1 < word_count) bytes[length++] = ' ';
  }
  bytes[length] = '\0';
  return text.intern_free();
}

static int _next_int(int maximum) {
  _random_state = (_random_state * 3877 + 29573) % 139968;
  return (int) ((int64_t) _random_state * maximum / 139968);
}

/* Like the reference, size the table at the first power of two of at least
   twice the word count, so counting never grows it. */
static uint64_t _count(String text, int word_count) {
  auto {
    unsigned capacity = 2;
    while (capacity < (unsigned) word_count * 2) capacity *= 2;
    MapSubInt counts = MapSubInt.new_capacity(capacity);
    foreach (Substr word in text) counts.increment(word);

    uint64_t checksum = 0;
    foreach ((Substr word, int count) in counts)
      checksum += 1 + word.len() * count;
    return checksum;
  }
}
