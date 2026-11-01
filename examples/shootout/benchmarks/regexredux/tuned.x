/* The Computer Language Benchmarks Game: regex-redux.
   Independent pattern counts use Threads, each with its own JIT-compiled
   Regexp and borrowed match-data block rather than capture Lists. */

import "pcre2" with Regexp;
#include <stdio.h>

class Count { String pattern, sequence; ulong matches; Thread worker; } *;

int main(void) {
  String input = Stdin.string();
  Regexp strip = auto Regexp.compile(">.*\\n|\\n", 0);
  strip.jit_compile(PCRE2_JIT_COMPLETE);
  String sequence = strip.replace_all(input, "");
  Array counts = [];
  int parallel = sequence.len() >= 65536;
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
    counts.push(Count.new(pattern, sequence, parallel));
  String replaced = _substitute(sequence);
  foreach (Count count in counts) {
    if (count.worker) {
      count.worker.join();
      count.worker.free();
    }
    printf("%s %lu\n", count.pattern, count.matches);
  }
  printf("\n%lu\n%lu\n%lu\n",
    (ulong) input.len(), (ulong) sequence.len(), (ulong) replaced.len());
  return 0;
}

static void Count.init(Count count, String pattern, String sequence, int parallel) {
  count.pattern = pattern;
  count.sequence = sequence;
  if (parallel) count.worker = Thread.start(_count, count);
  else _count(count);
}

static Var _count(Var input) {
  Count count = input;
  Regexp regexp = auto Regexp.compile(count.pattern, 0);
  regexp.jit_compile(PCRE2_JIT_COMPLETE);
  pcre2_match_data *data = regexp.native_match_data();
  PCRE2_SIZE *bounds = pcre2_get_ovector_pointer(data);
  ulong matches = 0, offset = 0;
  while (pcre2_jit_match(regexp.native(), (PCRE2_SPTR) count.sequence,
      count.sequence.len(), offset, 0, data, regexp.native_match_context()) >= 0) {
    matches++;
    offset = bounds[1];
  }
  count.matches = matches;
  return void;
}

static String _substitute(String sequence) {
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
  return replaced;
}
