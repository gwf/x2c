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
    else {
      String text = line.strip(NULL);
      if (text) sequence.write(text);
    }
  }
  _write(sequence);
  return 0;
}

static void _write(String sequence) {
  Buffer line = auto Buffer.new(0);
  for (int end = sequence.len(); end > 0;) {
    line.clear();
    int count = end > 60 ? 60 : end;
    for (int i = 0; i < count; i++)
      line.write_char(_complement(sequence[--end]));
    puts(line.str());
  }
}

static int _complement(int ch) {
  if (ch >= 'a' && ch <= 'z') ch -= 'a' - 'A';
  switch (ch) {
    case 'A': return 'T';
    case 'C': return 'G';
    case 'G': return 'C';
    case 'T': case 'U': return 'A';
    case 'M': return 'K';
    case 'R': return 'Y';
    case 'W': return 'W';
    case 'S': return 'S';
    case 'Y': return 'R';
    case 'K': return 'M';
    case 'V': return 'B';
    case 'H': return 'D';
    case 'D': return 'H';
    case 'B': return 'V';
    case 'N': return 'N';
    default: return ch;
  }
}
