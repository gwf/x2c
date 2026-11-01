/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

#include "typed-array.x"

int main(void) {
  ArrayChar sequence = ArrayChar.new();
  ArrayChar complements = ArrayChar.new();
  for (int i = 0; i < 128; i++) complements.push(i);
  String codes = "ACGTUMRWSYKVHDBN", pairs = "TGCAAKYWSRMBDHVN";
  for (int i = 0; i < codes.len(); i++) {
    complements[codes[i]] = pairs[i];
    complements[codes[i] + 'a' - 'A'] = pairs[i];
  }
  foreach (String line in Stdin) {
    if (line.startswith(">")) {
      _write(sequence, complements);
      sequence.clear();
      Stdout.puts(line);
    }
    else for (int i = 0; i < line.len(); i++)
      if (line[i] != '\n' && line[i] != '\r') sequence.push(line[i]);
  }
  _write(sequence, complements);
  return 0;
}

static void _write(ArrayChar sequence, ArrayChar complements) {
  for (int i = 0, j = (int) sequence.len() - 1; i <= j; i++, j--) {
    char first = complements[(unsigned char) sequence[i]];
    sequence[i] = complements[(unsigned char) sequence[j]];
    sequence[j] = first;
  }
  for (int start = 0; start < sequence.len(); start += 60) {
    int count = sequence.len() - start;
    if (count > 60) count = 60;
    Stdout.write_all((char *) sequence.bytes + start, count);
    Stdout.puts("\n");
  }
}
