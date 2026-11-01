/* The Computer Language Benchmarks Game: regex-redux.
   Independent pattern counts use Threads, each with its own JIT-compiled
   Regexp and borrowed match-data block rather than capture Lists. */

import "pcre2" with Regexp;
#include "typed-array.x"
#include <stdio.h>

class Count { String pattern; ArrayChar sequence; ulong matches; Thread worker; } *;

int main(void) {
  String input = Stdin.string();
  ArrayChar sequence = ArrayChar.new();
  _replace(">.*\\n|\\n", input, input.len(), NULL, sequence);
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
  size_t replaced = _substitute(sequence);
  foreach (Count count in counts) {
    if (count.worker) {
      count.worker.join();
      count.worker.free();
    }
    printf("%s %lu\n", count.pattern, count.matches);
  }
  printf("\n%lu\n%lu\n%lu\n",
    (ulong) input.len(), (ulong) sequence.len(), (ulong) replaced);
  return 0;
}

static void Count.init(Count count, String pattern, ArrayChar sequence, int parallel) {
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
  pcre2_code *code = regexp.native();
  pcre2_match_context *context = regexp.native_match_context();
  ulong matches = 0, offset = 0;
  const char *bytes = count.sequence.bytes ? count.sequence.bytes : "";
  size_t length = count.sequence.len();
  while (pcre2_jit_match(code, (PCRE2_SPTR) bytes,
      length, offset, 0, data, context) >= 0) {
    matches++;
    offset = bounds[1];
  }
  count.matches = matches;
  return void;
}

static size_t _substitute(ArrayChar sequence) {
  ArrayChar first = auto ArrayChar.new(), second = auto ArrayChar.new();
  ArrayChar current = sequence, next = first;
  foreach (List substitution in %(
    ("tHa[Nt]" "<4>")
    ("aND|caN|Ha[DS]|WaS" "<3>")
    ("a[NSt]|BY" "<2>")
    ("<[^>]*>" "|")
    ("\\|[^|][^|]*\\|" "-"))) {
    String (pattern, replacement) = substitution;
    _replace(pattern, current.bytes, current.len(), replacement, next);
    current = next;
    next = next == first ? second : first;
  }
  return current.len();
}

/* All six prescribed patterns consume at least one byte; replacements are
   literal text. Scratch buffers alternate instead of interning each pass. */
static void _replace(
  String pattern, const char *source, size_t length, String replacement,
  ArrayChar output) {
  Regexp regexp = auto Regexp.compile(pattern, 0);
  regexp.jit_compile(PCRE2_JIT_COMPLETE);
  pcre2_match_data *data = regexp.native_match_data();
  PCRE2_SIZE *bounds = pcre2_get_ovector_pointer(data);
  pcre2_code *code = regexp.native();
  pcre2_match_context *context = regexp.native_match_context();
  const char *bytes = source ? source : "";
  size_t offset = 0, size = replacement.len();
  output.clear();
  int result;
  while ((result = pcre2_jit_match(code, (PCRE2_SPTR) bytes, length,
      offset, 0, data, context)) >= 0) {
    ((Block) output).append(bytes + offset, bounds[0] - offset);
    ((Block) output).append(replacement, size);
    offset = bounds[1];
  }
  if (result != PCRE2_ERROR_NOMATCH)
    raise %(bad-state (library "PCRE2") (operation "replace") (code $result));
  ((Block) output).append(bytes + offset, length - offset);
}
