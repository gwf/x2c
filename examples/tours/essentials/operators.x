#include "system-macros.x"

/* Protocol adoption gives ordinary types shared operations. Set reuses Map
   storage. These methods make + a union, not arithmetic. */
typedef Map Set;
static Set Set.add(Set a, Set b) => a.copy().merge(b);
protocol Map(T) { T T.add(T, T); }
protocol Map(Set);

int main(void) {
  Set a = {apple: 1, pear: 1}, b = {pear: 1, bread: 1};
  Set combined = a + b;
  puts($dedent(%"
    Union: $(combined.keys().list().sort().repr())
    Original set size: $(a.len())"));
  return 0;
}
