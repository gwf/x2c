from pathlib import Path
p=Path('examples/shootout/benchmarks/regexredux/tuned.x');s=p.read_text();s=s.replace('int main(void) {','''#include <time.h>
static double _profile(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec * 1000.0 + now.tv_nsec / 1e6;
}

int main(void) {
  double begin = _profile(), stamp = begin;''');s=s.replace('  ArrayChar sequence =','  fprintf(stderr, "P read %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  ArrayChar sequence =',1).replace('  Array counts =','  fprintf(stderr, "P strip %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  Array counts =',1).replace('  size_t replaced =','  fprintf(stderr, "P launch %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  size_t replaced =',1).replace('  foreach (Count count in counts)','  fprintf(stderr, "P chain %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  foreach (Count count in counts)',1).replace('  return 0;','  fprintf(stderr, "P join_print %.6f\\nP total %.6f\\n", _profile() - stamp, _profile() - begin);\n  return 0;',1)
s=s.replace('  Count count = input;','  double stamp = _profile();\n  Count count = input;',1).replace('  pcre2_match_data *data','  fprintf(stderr, "P count_compile %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  pcre2_match_data *data',1).replace('  count.matches = matches;','  fprintf(stderr, "P count_match %.6f\\n", _profile() - stamp);\n  count.matches = matches;',1)
a=s.index('static void _replace(');part=s[a:].replace('  Regexp regexp =','  double stamp = _profile();\n  Regexp regexp =',1).replace('  pcre2_match_data *data','  fprintf(stderr, "P replacement_compile %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  pcre2_match_data *data',1).replace('  ((Block) output).append(bytes + offset, length - offset);','  ((Block) output).append(bytes + offset, length - offset);\n  fprintf(stderr, "P replacement_scan %.6f\\n", _profile() - stamp);');s=s[:a]+part;p.write_text(s)
