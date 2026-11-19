/* A typedef can reuse storage while defining new operations. Explicit
   adoption connects those methods to a protocol; names alone do not. */
typedef Map Set;
static Set Set.new(List keys) {
  Set set = {};
  foreach (Var key in keys) set[key] = 1;
  return set;
}
static Set Set.add(Set a, Set b) => a.copy().merge(b);
static Set Set.mul(Set a, Set b) =>
  Set.new(a.keys().filter(%!(Var key) => key in b));
protocol Map(T) { T T.add(T, T); T T.mul(T, T); }
protocol Map(Set);

int main(void) {
  Set a = Set.new(%(apple pear)), b = Set.new(%(pear bread));
  Set combined = a + b, common = a * b;
  // Map traversal has no promised order; sort before presenting keys.
  printf("Union: %s\nIntersection: %s\n",
         combined.keys().list().sort().repr(),
         common.keys().list().sort().repr());
  return 0;
}
