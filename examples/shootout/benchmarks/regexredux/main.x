/* The Computer Language Benchmarks Game: regex-redux.
   PCRE2's ordinary Regexp API performs the prescribed searches and ordered
   substitutions. The contributed Python reference uses its standard engine. */

import "pcre2" with Regexp;
#include <stdio.h>

int main(void) {
  String input = Stdin.string();
  Regexp strip = auto Regexp.compile(">.*\\n|\\n", 0);
  String sequence = strip.replace_all(input, "");
  foreach (String pattern in %(
    "agggtaaa|tttaccct"
    "[cgt]gggtaaa|tttaccc[acg]"
    "a[act]ggtaaa|tttacc[agt]t"
    "ag[act]gtaaa|tttac[agt]ct"
    "agg[act]taaa|ttta[agt]cct"
    "aggg[acg]aaa|ttt[cgt]ccct"
    "agggt[cgt]aa|tt[acg]accct"
    "agggta[cgt]a|t[acg]taccct"
    "agggtaa[cgt]|[acg]ttaccct"))
    auto {
      Regexp regexp = auto Regexp.compile(pattern, 0);
      printf("%s %lu\n", pattern, (ulong) regexp.find_all(sequence).len());
    }
  String replaced = sequence;
  foreach (List substitution in %(
    ("tHa[Nt]" "<4>")
    ("aND|caN|Ha[DS]|WaS" "<3>")
    ("a[NSt]|BY" "<2>")
    ("<[^>]*>" "|")
    ("\\|[^|][^|]*\\|" "-"))) {
    String (pattern, replacement) = substitution;
    Regexp regexp = auto Regexp.compile(pattern, 0);
    replaced = regexp.replace_all(replaced, replacement);
  }
  printf("\n%lu\n%lu\n%lu\n",
    (ulong) input.len(), (ulong) sequence.len(), (ulong) replaced.len());
  return 0;
}
