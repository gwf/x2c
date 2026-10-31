/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

#include "substring-map.x"

int main(void) {
  String sequence = _read();
  for (int width = 1; width <= 2; width++) auto {
    MapSubInt counts = _count(sequence, width);
    Map frequencies = counts.strings();
    Array keys = [];
    foreach ((String key, Var count) in frequencies) keys.push(key);
    keys.sort_with(%!(String a, String b) => {
      int difference = frequencies[b].int() - frequencies[a].int();
      return difference ? difference : a.compare(b);
    });
    foreach (String key in keys)
      printf("%s %.3f\n", key,
        100.0 * frequencies[key].int() / (sequence.len() - width + 1));
    puts("");
  }
  foreach (String key in %(
    "GGT" "GGTA" "GGTATT" "GGTATTTTAATT" "GGTATTTTAATTTATAGT")) auto {
    MapSubInt counts = _count(sequence, key.len());
    Substr query = key.substring(0, key.len());
    printf("%d\t%s\n", _lookup(counts, query), key);
  }
  return 0;
}
static String _read(void) {
  Buffer sequence = auto Buffer.new(0);
  int found = 0;
  foreach (String line in Stdin) {
    if (!found) {
      if (line.startswith(">THREE")) found = 1;
    }
    else {
      if (line.startswith(">")) break;
      sequence.write(line.strip(NULL));
    }
  }
  return sequence.str().upper();
}

static MapSubInt _count(String sequence, int width) {
  MapSubInt counts = MapSubInt.new();
  for (int i = 0; i + width <= sequence.len(); i++)
    counts.increment(sequence.substring(i, width));
  return counts;
}

/* MapSubInt exposes counts through iteration, without a lookup operation. */
static int _lookup(MapSubInt counts, Substr query) {
  unsigned cursor = 0;
  Substr key;
  int count;
  while (counts.try_next(cursor, key, count))
    if (key.equal(query)) return count;
  return 0;
}
