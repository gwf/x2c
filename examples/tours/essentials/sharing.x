#include "system-macros.x"

/* Immutable values and mutable objects have different copying rules.
   Canonical Strings and Lists share equal structure. An Array copy here is
   another handle to the same object; mutation is visible through both. */
int main(void) {
  List tail = %(2 3), whole = %(1 @tail);
  Array numbers = [2, 3], same = numbers;
  same[0] = 9;
  puts($dedent(%"
    Shared list tail: $(whole.cdr() === tail)
    Array after mutation: $(numbers.repr())"));
  String greeting = "hello" + " world", expected = "hello world";
  printf("Canonical string identity: %d\n", greeting === expected);
  Map counts = {zero: 0};
  Var found;
  int present = counts.try_get(<zero>, found);
  puts($dedent(%"
    Zero key present: $present
    Stored value: $found
    Missing key present: $(<missing> in counts)"));
  return 0;
}
