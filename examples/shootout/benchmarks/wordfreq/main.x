/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/wordfreq-idiomatic main.x
 *   /tmp/wordfreq-idiomatic 50000 10
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int _random_state = 42;

static int _next_int(int maximum) {
  _random_state = (_random_state * 3877 + 29573) % 139968;
  return (int) ((int64_t) _random_state * maximum / 139968);
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

static uint64_t _count(String text) {
  Scope.retain();
  defer Scope.release();
  Map counts = %{};
  foreach (String word, text.words()) counts[word] += 1;

  uint64_t checksum = counts.len();
  foreach (Var (word, count), counts)
    checksum += word.string().len() * count.int();
  return checksum;
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  String text = _make_text(atoi(argv[1]));
  uint64_t checksum = 0;
  for (int i = 0; i < atoi(argv[2]); i++)
    checksum = checksum * 33 + _count(text);
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}
