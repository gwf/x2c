/* `in` is a name where an operand begins and the operator where one
   ended. After the `)` of a condition or a cast, or after a block, an
   operand begins, so the parser reads the name; a parenthesized value or
   macro hole is followed by the operator. */
macro Expression $has($key, Expr $table) => ($key) in $table;

static int total;

static int in(int count) {
  total += count;
  return count;
}

static int doubled(void) {
  int in = 3;
  if (in) in++;
  return (int) in * 2;
}

int main(void) {
  Map units = {"a": 1};
  if (total == 0) in(1);
  (void) in(2);
  if (total == 3) {
    total++;
  }
  in(4);
  printf("%d %d\n", total, doubled());
  printf("%d %d %d\n", ("a") in units, $has("a", units), $has("b", units));
  return 0;
}
