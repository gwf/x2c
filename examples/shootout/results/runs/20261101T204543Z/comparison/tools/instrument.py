from pathlib import Path
p=Path('packages/pcre2/src/pcre2.x');s=p.read_text();pos=s.index('String Regexp.substitute(');s=s[:pos]+'''#include <time.h>
static double _pcre_profile(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec * 1000.0 + now.tv_nsec / 1e6;
}

'''+s[pos:];a=s.index('String Regexp.substitute(');b=s.index('String Regexp.replace(',a);part=s[a:b].replace('  PCRE2_SIZE length = 0;','  double stamp = _pcre_profile();\n  PCRE2_SIZE length = 0;');part=part.replace('  if (result != PCRE2_ERROR_NOMEMORY','  fprintf(stderr, "P size %.6f %d\\n", _pcre_profile() - stamp, subject.len());\n  if (result != PCRE2_ERROR_NOMEMORY',1).replace('  result = pcre2_substitute(','  stamp = _pcre_profile();\n  result = pcre2_substitute(',1).replace('  if (result < 0) {','  fprintf(stderr, "P write %.6f %d\\n", _pcre_profile() - stamp, subject.len());\n  if (result < 0) {',1).replace('  return output.intern_free();','  stamp = _pcre_profile();\n  String canonical = output.intern_free();\n  fprintf(stderr, "P intern %.6f %d\\n", _pcre_profile() - stamp, canonical.len());\n  return canonical;');s=s[:a]+part+s[b:];p.write_text(s)
p=Path('examples/shootout/benchmarks/regexredux/tuned.x');s=p.read_text();s=s.replace('int main(void) {','''#include <time.h>
static double _profile(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec * 1000.0 + now.tv_nsec / 1e6;
}

int main(void) {
  double begin = _profile(), stamp = begin;''');s=s.replace('  Regexp strip =','  fprintf(stderr, "P read %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  Regexp strip =',1).replace('  String sequence =','  fprintf(stderr, "P strip_compile %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  String sequence =',1).replace('  Array counts =','  fprintf(stderr, "P strip %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  Array counts =',1).replace('  String replaced =','  fprintf(stderr, "P launch %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  String replaced =',1).replace('  foreach (Count count in counts)','  fprintf(stderr, "P chain %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  foreach (Count count in counts)',1).replace('  return 0;','  fprintf(stderr, "P join_print %.6f\\nP total %.6f\\n", _profile() - stamp, _profile() - begin);\n  return 0;',1)
s=s.replace('  Count count = input;','  double stamp = _profile();\n  Count count = input;',1).replace('  pcre2_match_data *data','  fprintf(stderr, "P count_compile %.6f\\n", _profile() - stamp);\n  stamp = _profile();\n  pcre2_match_data *data',1).replace('  count.matches = matches;','  fprintf(stderr, "P count_match %.6f\\n", _profile() - stamp);\n  count.matches = matches;',1);p.write_text(s)
