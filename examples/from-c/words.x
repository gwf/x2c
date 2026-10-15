// C sees an ordinary C prototype in the generated words.h.
void count_words(const char *text) {
  String words = text;
  Map counts = {};
  foreach (String word, words.lower().words())
    counts[word] += 1;
  foreach (Var (word, n), counts.enumerate().array().sort())
    puts(%"$word $n");
}
