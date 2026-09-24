// `in` separates a foreach declaration from its collection; a comma still
// does, and `in` stays the membership operator elsewhere.
int main(void) {
  List values = %(1 2 3);
  Map map = {"a": 1};
  int total = 0;
  foreach (Var value in values) total += value.integer();
  foreach (Var (key, value) in map) printf("%s=%ld\n", key, value.integer());
  foreach (String word in ["x", "y"]) printf("%s", word);
  foreach (Var value, values) if (value in %(2)) total *= 10;
  printf("\n%d\n", total);
  return 0;
}
