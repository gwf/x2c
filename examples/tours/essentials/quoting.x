#include "system-macros.x"

/* Quoted names are data, not variable reads. $ inserts one value; @ splices
   elements. Bare Map keys name Atoms. */
int main(void) {
  int n = 2;
  List pair = $(n, n + 1);
  puts($dedent(%"
    Quoted name: $(%(n).repr())
    Inserted value: $($(n).repr())
    Nested list: $(%($pair).repr())
    Spliced list: $(%(@pair).repr())"));
  String key = "answer";
  Map named = {key: n}, evaluated = ${key: n};
  puts($dedent(%"
    Bare keys: $(named.keys().list().repr())
    Evaluated keys: $(evaluated.keys().list().repr())"));
  return 0;
}
