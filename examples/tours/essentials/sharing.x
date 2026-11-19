/* Immutable values and mutable objects have different copying rules.
   Canonical Strings and Lists share equal structure. An Array copy here is
   another handle to the same object; mutation is visible through both. */
int main(void) {
  auto {
    List tail = %(2 3), whole = %(1 @tail);
    Array numbers = [2, 3], same = numbers;
    same[0] = 9;
    printf("sharing: tail %d; array %s\n",
           whole.cdr() === tail, numbers.repr());
    String greeting = "hello" + " world", expected = "hello world";
    printf("   canonical text %d\n", greeting === expected);
    Map counts = {zero: 0};
    Var found;
    int present = counts.try_get(<zero>, found);
    printf("   zero present %d, value %s; missing %d\n",
           present, found, <missing> in counts);
  }
  return 0;
}
