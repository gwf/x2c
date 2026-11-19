#include "system-macros.x"

/* Quoted names are data, not variable reads. $ inserts one value; @ splices
   elements. Bare Map keys name Atoms. */
int main(void) {
  int n = 2;
  List pair = $(n, n + 1);
  printf("Quoted name: %s\nInserted value: %s\n", %(n).repr(), $(n).repr());
  printf("Nested list: %s\nSpliced list: %s\n", %($pair).repr(), %(@pair).repr());
  String key = "answer";
  Map named = {key: n}, evaluated = ${key: n};
  puts($dedent(%"
    Bare keys: $(named.keys().list().repr())
    Evaluated keys: $(evaluated.keys().list().repr())"));
  return 0;
}
