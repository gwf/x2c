/*  counting.x -- task-oriented file and collection tutorial */


int main(int argc, char **argv) {
  if (argc != 2) {
    Stderr.printf("usage: %s FILE\n", argv[0]);
    return 2;
  }

  Scope.retain();
  defer Scope.release();
  Map counts = %{};
  int lines = 0, words = 0;

  try {
    File input = File.open(argv[1], "r");
    defer input.close();
    foreach(String line, input) {
      lines++;
      foreach(String word, line.lower().words()) {
        Var old;
        long count = counts.try_get(word, &old) ? old.integer() : 0;
        counts[word] = count + 1;
        words++;
      }
    }
  }
  catch %(not-found *): {
    Stderr.printf("cannot open %s\n", argv[1]);
    return 2;
  }
  catch %(io-fail *): {
    Stderr.printf("cannot read %s\n", argv[1]);
    return 2;
  }

  Var beta = 0;
  counts.try_get("beta", &beta);
  printf("lines=%d words=%d beta=%ld\n", lines, words, beta.integer());
  return 0;
}
