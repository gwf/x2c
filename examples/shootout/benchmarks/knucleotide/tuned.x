/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

#include "substring-map.x"

class Batch { String sequence, key, output; int width; Thread worker; } *;

int main(void) {
  String sequence = _read();
  Array batches = [];
  foreach (String key in %("A" "AA" "GGT" "GGTA" "GGTATT"
    "GGTATTTTAATT" "GGTATTTTAATTTATAGT")) {
    Batch batch = Batch.new();
    batch.sequence = sequence;
    batch.key = key;
    batch.width = key.len();
    batch.worker = Thread.start(_run, batch);
    batches.push(batch);
  }
  foreach (Batch batch in batches) {
    batch.worker.join();
    batch.worker.free();
    printf("%s", batch.output);
  }
  return 0;
}

static Var _run(Var input) {
  Batch batch = input;
  MapSubInt counts = _count(batch.sequence, batch.width);
  Buffer output = auto Buffer.new();
  if (batch.width <= 2) {
    Map frequencies = counts.strings();
    Array keys = [];
    foreach ((String key, Var count) in frequencies) keys.push(key);
    keys.sort_with(%!(String a, String b) => {
      int difference = frequencies[b].int() - frequencies[a].int();
      return difference ? difference : a.compare(b);
    });
    foreach (String key in keys)
      output.printf("%s %.3f\n", key,
        100.0 * frequencies[key].int() / (batch.sequence.len() - batch.width + 1));
    output.write("\n");
  }
  else {
    Substr query = batch.key.substring(0, batch.width);
    output.printf("%d\t%s\n", _lookup(counts, query), batch.key);
  }
  batch.output = output;
  return void;
}

static String _read(void) {
  Buffer sequence = auto Buffer.new();
  int found = 0;
  foreach (String line in Stdin) {
    if (!found) {
      if (line.startswith(">THREE")) found = 1;
    }
    else {
      if (line.startswith(">")) break;
      sequence.write(line.strip());
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

static void Batch.init(Batch batch) {}
