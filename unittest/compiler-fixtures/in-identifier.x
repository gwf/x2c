/* After a `)`, `in` is a name where an operand begins and the operator
   where one ended. A condition or a cast comes before an operand, so the
   parser reads the name there; a parenthesized value or macro hole comes
   before the operator. */
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
  printf("%d %d\n", total, doubled());
  printf("%d %d %d\n", ("a") in units, $has("a", units), $has("b", units));
  return 0;
}
