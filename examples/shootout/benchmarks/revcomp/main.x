/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

int main(void) {
  Buffer sequence = auto Buffer.new(0);
  foreach (String line in Stdin) {
    if (line.startswith(">")) {
      _write(sequence);
      sequence.clear();
      Stdout.puts(line);
    }
    else sequence.write(line.strip(NULL));
  }
  _write(sequence);
  return 0;
}

static void _write(String sequence) {
  String reverse = sequence[::-1].upper().map(%!(int ch) =>
    _complement(ch));
  for (int start = 0; start < reverse.len(); start += 60) {
    int end = start + 60 < reverse.len() ? start + 60 : reverse.len();
    puts(reverse[start:end]);
  }
}

static int _complement(int ch) {
  String codes = "ACGTUMRWSYKVHDBN", complements = "TGCAAKYWSRMBDHVN";
  for (int i = 0; i < codes.len(); i++)
    if (codes[i] == ch) return complements[i];
  return ch;
}
