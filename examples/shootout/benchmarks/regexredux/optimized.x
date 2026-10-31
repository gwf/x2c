/* The Computer Language Benchmarks Game: regex-redux.
   The optimized version JIT-compiles PCRE2 patterns and counts through its
   borrowed match-data block instead of materializing capture Lists. */

import "pcre2" with Regexp;
#include <stdio.h>

int main(void) {
  String input = Stdin.string();
  Regexp strip = auto Regexp.compile(">.*\\n|\\n", 0);
  strip.jit_compile(PCRE2_JIT_COMPLETE);
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
      regexp.jit_compile(PCRE2_JIT_COMPLETE);
      printf("%s %lu\n", pattern, _count(regexp, sequence));
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
    replaced = regexp.jit_compile(PCRE2_JIT_COMPLETE)
      .replace_all(replaced, replacement);
  }
  printf("\n%lu\n%lu\n%lu\n",
    (ulong) input.len(), (ulong) sequence.len(), (ulong) replaced.len());
  return 0;
}

static ulong _count(Regexp regexp, String sequence) {
  pcre2_match_data *data = regexp.native_match_data();
  PCRE2_SIZE *bounds = pcre2_get_ovector_pointer(data);
  ulong count = 0, offset = 0;
  while (pcre2_jit_match(regexp.native(), (PCRE2_SPTR) sequence,
      sequence.len(), offset, 0, data, regexp.native_match_context()) >= 0) {
    count++;
    offset = bounds[1];
  }
  return count;
}
