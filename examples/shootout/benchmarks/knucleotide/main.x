/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

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
  Map counts = _count(batch.sequence, batch.width);
  Buffer output = auto Buffer.new();
  if (batch.width <= 2) {
    Array keys = [];
    foreach ((String key, Var count) in counts) keys.push(key);
    keys.sort_with(%!(String a, String b) => {
      int difference = counts[b].int() - counts[a].int();
      return difference ? difference : a.compare(b);
    });
    foreach (String key in keys)
      output.printf("%s %.3f\n", key,
        100.0 * counts[key].int() / (batch.sequence.len() - batch.width + 1));
    output.write("\n");
  }
  else output.printf("%d\t%s\n", counts.getdefault(batch.key, 0), batch.key);
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

static Map _count(String sequence, int width) {
  Map counts = {};
  int last = sequence.len() - width;
  for (int i = 0; i <= last; i++) {
    String key = sequence[i:i + width];
    counts[key] = counts.getdefault(key, 0).int() + 1;
  }
  return counts;
}

static void Batch.init(Batch batch) {}
