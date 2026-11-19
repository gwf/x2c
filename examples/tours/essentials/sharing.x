/* Immutable values and mutable objects have different copying rules.
   Canonical Strings and Lists share equal structure. An Array copy here is
   another handle to the same object; mutation is visible through both. */
int main(void) {
  List tail = %(2 3), whole = %(1 @tail);
  Array numbers = [2, 3], same = numbers;
  same[0] = 9;
  printf("Shared list tail: %d\nArray after mutation: %s\n",
         whole.cdr() === tail, numbers.repr());
  String greeting = "hello" + " world", expected = "hello world";
  printf("Canonical string identity: %d\n", greeting === expected);
  Map counts = {zero: 0};
  Var found;
  int present = counts.try_get(<zero>, found);
  printf("Zero key present: %d\nStored value: %s\nMissing key present: %d\n",
         present, found, <missing> in counts);
  return 0;
}
