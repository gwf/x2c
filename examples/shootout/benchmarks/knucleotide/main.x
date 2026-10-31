/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

int main(void) {
  String sequence = _read();
  for (int width = 1; width <= 2; width++) auto {
    Map counts = _count(sequence, width);
    Array keys = [];
    foreach ((String key, Var count) in counts) keys.push(key);
    keys.sort_with(%!(String a, String b) => {
      int difference = counts[b].int() - counts[a].int();
      return difference ? difference : a.compare(b);
    });
    foreach (String key in keys)
      printf("%s %.3f\n", key,
        100.0 * counts[key].int() / (sequence.len() - width + 1));
    puts("");
  }
  foreach (String key in %(
    "GGT" "GGTA" "GGTATT" "GGTATTTTAATT" "GGTATTTTAATTTATAGT")) auto {
    Map counts = _count(sequence, key.len());
    printf("%d\t%s\n", counts.getdefault(key, 0), key);
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

static Map _count(String sequence, int width) {
  Map counts = {};
  for (int i = 0; i + width <= sequence.len(); i++) {
    String key = sequence[i:i + width];
    counts[key] = counts.getdefault(key, 0).int() + 1;
  }
  return counts;
}
