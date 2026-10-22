#include "substring-map.x"

typedef Substr Word;
typedef int Count;
static int source_calls;

static MapSubInt source(void) {
  ++source_calls;
  MapSubInt result = MapSubInt.new();
  foreach (Substr word in "alpha beta alpha") result.increment(word);
  return result;
}

int main(void) {
  int total = 0, bytes = 0;
  foreach ((Word word, Count count) in source()) {
    total += count;
    bytes += word.len();
  }
  Map entries = {"a": 4};
  foreach ((String word, int count) in entries) total += word.len() * count;
  Array ranked = [%(2 "beta"), %(1 "alpha")];
  foreach ((int count, String word) in ranked.sort())
    printf("%d %s\n", count, word);
  printf("total=%d bytes=%d calls=%d\n", total, bytes, source_calls);
  return 0;
}
